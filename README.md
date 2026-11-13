# Azure Landing Zone — Terraform + GitHub Actions

> 👉 **Nouveau sur le projet ? Commencez par [GUIDE-PAS-A-PAS.md](GUIDE-PAS-A-PAS.md)** (vocabulaire, lancement étape par étape, explication de chaque fichier).

Implémentation d'une landing zone Azure alignée sur l'architecture de référence **Azure Landing Zones (CAF)**, version 2025+ (management group et souscription **Security** dédiés), déployée en **stages Terraform indépendants** et pilotée par **GitHub Actions avec OIDC** (aucun secret).

> Hypothèses par défaut : région principale **France Central**, topologie **hub & spoke**, Azure Firewall **Premium**, Microsoft Sentinel dans la souscription Security. Tout est paramétrable.

---

## 1. Architecture

### 1.1 Hiérarchie de management groups

```
Tenant Root Group
└── contoso                         (racine intermédiaire — créée par bootstrap/)
    ├── contoso-platform
    │   ├── contoso-management      ◄─ sub "management"
    │   ├── contoso-connectivity    ◄─ sub "connectivity"
    │   ├── contoso-identity        ◄─ sub "identity"
    │   └── contoso-security        ◄─ sub "security"
    ├── contoso-landingzones
    │   ├── contoso-corp            ◄─ subs applicatives internes (vending)
    │   └── contoso-online          ◄─ subs applicatives exposées Internet
    ├── contoso-sandbox             ◄─ subs d'expérimentation (isolées)
    └── contoso-decommissioned      ◄─ subs en fin de vie
```

Chaque niveau porte un **archétype** de la bibliothèque ALZ officielle (policies et rôles hérités). Exemples de garde-fous appliqués :

| Niveau | Principaux garde-fous (bibliothèque ALZ) |
|---|---|
| Racine | Microsoft Cloud Security Benchmark, Defender for Cloud (tous plans), Activity Logs → Log Analytics, diagnostics, AMA/VM Insights, localisation autorisée (ajout local) |
| Platform / Landing Zones | Change Tracking, Defender SQL (AMA), sauvegarde, chiffrement, TLS, interdiction RDP/SSH depuis Internet, sous-réseaux sans NSG interdits |
| Connectivity | Protection DDoS des VNets (si activée) |
| Corp | Interdiction des IP publiques et endpoints publics, DNS privé automatique des private endpoints |
| Sandbox | Interdiction du peering et des passerelles (isolation) |
| Decommissioned | Interdiction de créer des ressources, arrêt des VM |

### 1.2 Souscriptions et resource groups

| Souscription | MG | Resource groups | Ressources clés |
|---|---|---|---|
| **management** | Management | `rg-<org>-tfstate-<loc>` | Stockage d'état Terraform (Entra ID only, versioning, soft delete, verrou) |
| | | `rg-<org>-cicd-<loc>` | Identités managées CI/CD (plan / apply) fédérées GitHub |
| | | `rg-<org>-management-<loc>` | Log Analytics plateforme, identité AMA, 3 DCR (VM Insights, Change Tracking, Defender SQL), stockage d'archive WORM, action group, alerte Service Health |
| **security** | Security | `rg-<org>-security-<loc>` | Log Analytics SOC + **Microsoft Sentinel**, règle d'incidents Defender for Cloud, journaux Entra ID (option), Key Vault Premium (RBAC, purge protection) |
| **connectivity** | Connectivity | `rg-<org>-hub-<loc>` | VNet hub, Azure Firewall Premium + policy (IDPS, threat intel en Deny, proxy DNS), Bastion, passerelle VPN (option), DNS Private Resolver |
| | | `rg-<org>-dns-<loc>` | ~30 zones `privatelink.*` liées au hub |
| | | `rg-<org>-ddos-<loc>` | Plan DDoS Network Protection (option) |
| **identity** | Identity | `rg-<org>-identity-<loc>` | Spoke identité (AD DS / Entra Connect) peeré au hub, NSG AD |
| **landing zones** (N) | Corp / Online / Sandbox | `rg-<lz>-network-<loc>`, `rg-<lz>-identity-<loc>` | Spoke, UDR → pare-feu, NSG, RBAC équipe, identité CI/CD de l'équipe, budget |

### 1.3 Flux de journalisation et sécurité

```
 Toutes les souscriptions ──(policy ALZ DINE)──► Activity Logs + diagnostics ──► LAW plateforme (management)
 VM / Arc ──(policy AMA + DCR)───────────────────► VM Insights, Change Tracking ─► LAW plateforme
 LAW plateforme ──(data export)──────────────────► Stockage d'archive (WORM, cool → archive, N années)
 Entra ID (sign-ins, audit, risques) ─────────────► LAW Sentinel (security)
 Defender for Cloud (plans activés par policy) ──► alertes ─► incidents Sentinel
 Azure Firewall (tables AZFW* dédiées) ──────────► LAW plateforme
 Key Vault plateforme (allLogs) ──────────────────► LAW Sentinel
```

Séparation des responsabilités : l'exploitation (management) et le SOC (security) ont chacun leur workspace et leurs droits ; le SOC peut lire le workspace plateforme via RBAC si besoin (requêtes cross-workspace).

### 1.4 Réseau (plan d'adressage par défaut)

| Plage | Usage |
|---|---|
| `10.0.0.0/22` | Hub — `AzureFirewallSubnet 10.0.0.0/26`, `GatewaySubnet 10.0.0.64/27`, `AzureBastionSubnet 10.0.0.128/26`, DNS resolver in/out `10.0.1.0/28` `10.0.1.16/28` |
| `10.0.4.0/24` | Spoke identité |
| `10.1.0.0/16` | Landing zones Corp/Online (un /24 par LZ par défaut) |
| `172.16.0.0/16` | Sandboxes (jamais peerées) |

Tout le trafic sortant des spokes passe par le pare-feu (UDR `0.0.0.0/0`, propagation BGP désactivée, `defaultOutboundAccess = false`). Le DNS des spokes pointe vers le **proxy DNS du pare-feu**, qui résout les zones privatelink liées au hub.

---

## 2. Structure du dépôt

```
.
├── bootstrap/                      # Exécuté 1 fois en local (état, MG racine, identités OIDC, environnements GitHub)
├── config/common.tfvars            # Variables partagées par tous les stages
├── modules/
│   ├── conventions/                # Nommage CAF + IDs déterministes
│   ├── spoke-network/              # Spoke azurerm (souscription connue)
│   └── landing-zone/               # Subscription vending (azapi, souscription dynamique)
├── stages/
│   ├── 00-governance/              # MG + policies ALZ (avm-ptn-alz) + placement + RBAC
│   │   └── lib/                    # Bibliothèque ALZ locale (version figée + architecture)
│   ├── 10-management/
│   ├── 20-security/
│   ├── 30-connectivity/
│   ├── 40-identity/
│   └── 50-subscription-vending/
│       ├── landing-zones/*.yaml    # 1 fichier = 1 landing zone (GitOps) — vide au départ
│       └── examples/               # modèles à copier dans landing-zones/
├── scripts/rename-org.sh
└── .github/
    ├── workflows/
    │   ├── terraform-stage.yml     # Réutilisable : plan (Reader) → apply du plan sauvegardé (approbation)
    │   ├── ci.yml                  # PR : fmt, validate, tflint, checkov (SARIF), plans commentés
    │   ├── cd.yml                  # main : déploiement ordonné des stages
    │   └── drift-detection.yml     # Quotidien : plan → issue "drift"
    ├── CODEOWNERS · dependabot.yml · pull_request_template.md
    └── ISSUE_TEMPLATE/landing-zone-request.yml
```

**Pourquoi des stages séparés ?** Rayon d'impact limité (un `apply` réseau ne peut pas toucher aux policies), plans plus rapides, propriétaires distincts (CODEOWNERS), et états séparés (`<stage>.tfstate`). Les dépendances passent par le module `conventions` (IDs calculés) ou `terraform_remote_state` (sorties de 30-connectivity).

---

## 3. Prérequis

1. **Tenant Entra ID** avec un compte Global Administrator pouvant utiliser *Elevate access* (User Access Administrator sur `/`) — uniquement pour le bootstrap.
2. **4 souscriptions plateforme** créées (management, connectivity, identity, security) — via EA/MCA ou portail.
3. **Facturation (pour le vending)** : rôle *Enrollment account subscription creator* (EA) ou *Azure subscription creator* sur la section de facture (MCA) attribué à l'identité **apply** — opération manuelle côté facturation.
4. **Paramètres de hiérarchie** (Portail > Management groups > Settings) : MG par défaut des nouvelles souscriptions = `contoso-sandbox` ; activer *Require write permissions for creating new management groups*.
5. **Dépôt GitHub** + équipe d'approbateurs (`cloud-platform-approvers`), Terraform ≥ 1.9, Azure CLI, `gh`.
6. **Groupes Entra ID** pour le RBAC (idéalement éligibles via PIM) : admins plateforme, réseau, SecOps, auditeurs, équipes applicatives.

---

## 4. Déploiement

### 4.1 Personnalisation

```bash
./scripts/rename-org.sh monorg "Mon Organisation"
# puis renseigner config/common.tfvars (IDs de souscriptions, e-mail, tags)
# et les terraform.tfvars de chaque stage
```

### 4.2 Bootstrap (une fois, en local)

```bash
az login --tenant <tenant-id>
# Portail Entra ID > Properties > "Access management for Azure resources" = Yes (elevate access)
export GITHUB_TOKEN=$(gh auth token)       # ou PAT fine-grained (Administration, Environments, Variables)

cd bootstrap
cp terraform.tfvars.example terraform.tfvars   # compléter
terraform init && terraform apply

# Migration de l'état local vers le stockage créé
# -> décommenter le bloc backend dans versions.tf, puis :
terraform init -migrate-state

# Reporter la sortie "tfstate" dans config/common.tfvars
terraform output tfstate
```

Puis **désactiver l'elevate access**. Le bootstrap a créé :
- les environnements GitHub `alz-plan` (libre) et `alz-apply` (approbation obligatoire, branches protégées uniquement, pas d'auto-approbation) ;
- les variables `AZURE_TENANT_ID`, `TFSTATE_*` (dépôt) et `AZURE_CLIENT_ID` (par environnement).

### 4.3 Fichiers de verrouillage des providers

Générer et **versionner** les `.terraform.lock.hcl` pour garantir que plan et apply utilisent exactement les mêmes providers :

```bash
for d in stages/*/; do (cd "$d" && terraform init -backend=false && \
  terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=windows_amd64); done
```

### 4.4 Protection de la branche `main` (ruleset GitHub)

- PR obligatoire, 1-2 approbations, *Require review from Code Owners*
- Status checks requis : `fmt · validate · tflint · checkov` et les jobs `plan`
- Historique linéaire, pas de force-push, commits signés recommandés

### 4.5 Premier déploiement

Merger sur `main` déclenche `cd.yml`. Ordre et approbations :

```
00-governance → 10-management → (20-security ∥ 30-connectivity) → 40-identity
                                                                 → 50-subscription-vending
```

Pour chaque stage : plan avec l'identité **Reader** → le plan apparaît dans le résumé du run → un approbateur valide l'environnement `alz-apply` → apply **du plan sauvegardé** avec l'identité **Owner**. Un stage sans changement est sauté sans approbation.

> Au tout premier passage, les plans de PR de 40/50 échouent tant que l'état de 30-connectivity n'existe pas : c'est attendu.

> Les policies DINE/Modify ne s'appliquent automatiquement qu'aux **nouvelles** ressources. Pour l'existant, lancer des tâches de remédiation (Portail Policy > Remediation, ou `az policy remediation create`) une fois les stages 10 et 30 déployés.

---

## 5. Modèle CI/CD et sécurité de la chaîne

| Élément | Choix |
|---|---|
| Authentification | **OIDC** GitHub → identités managées fédérées ; *subject* lié à l'environnement (`repo:<org>/<repo>:environment:alz-apply`). Aucun secret, aucune rotation. |
| Séparation plan/apply | Identité `plan` = Reader + accès blob (verrou d'état) ; identité `apply` = Owner sur la racine intermédiaire, obtenable **uniquement** depuis l'environnement `alz-apply` (approbation + branche protégée). |
| Intégrité | L'apply exécute le fichier de plan **approuvé** (artefact + lock file) ; un plan obsolète est refusé. |
| Concurrence | `concurrency: alz-cd` (jamais annulé) + verrous de lease sur le blob d'état. |
| Qualité / sécurité | `terraform fmt`, `validate`, **tflint** (ruleset azurerm), **checkov** (SARIF → onglet Security), pre-commit + gitleaks en local, Dependabot (providers et actions). |
| Dérive | Plan quotidien (jours ouvrés) → issue `drift` par stage. |
| Traçabilité | Plan commenté sur chaque PR, résumé par run, historique des déploiements par environnement GitHub, versioning du blob d'état. |

### Self-service des équipes applicatives (vending)

1. L'équipe ouvre une issue *Demande de landing zone*.
2. L'équipe plateforme (ou l'équipe elle-même) ouvre une PR ajoutant `stages/50-subscription-vending/landing-zones/<lz>.yaml` (réservation IP dans l'IPAM).
3. Revue réseau + FinOps (CODEOWNERS), merge, approbation → la souscription est livrée avec réseau, RBAC, budget et une identité CI/CD fédérée sur **leur** dépôt (`cicd_client_id` en sortie).
4. Décommissionnement : passer `archetype: decommissioned` (jamais supprimer le YAML : `prevent_destroy` sur l'alias protège contre l'annulation accidentelle).

---

## 6. Durcissement recommandé (au-delà de ce socle)

- **Restreindre l'identité apply** : remplacer Owner par *Contributor* + *Role Based Access Control Administrator* avec **condition ABAC** interdisant d'attribuer Owner/UAA/RBAC Admin ; une identité par stage (scopes plus fins).
- **Runners auto-hébergés** dans un spoke (ex : GitHub ARC ou Container Apps jobs) + `state_public_network_access_enabled = false` + private endpoint sur le stockage d'état et le Key Vault.
- **AMPLS** (Azure Monitor Private Link Scope) et `internet_ingestion_enabled = false` sur les workspaces.
- **AMBA** (Azure Monitor Baseline Alerts) : ajouter la dépendance `platform/amba` à `lib/alz_library_metadata.json` pour un socle d'alertes complet sur toutes les souscriptions.
- **Inspection TLS** du pare-feu Premium (certificat d'AC intermédiaire dans le Key Vault).
- **Verrouiller l'immutabilité** du stockage d'archive (`state = "Locked"`) une fois la durée validée par la conformité.
- **Break-glass** : 2 comptes d'urgence exclus de l'accès conditionnel, surveillés par Sentinel.
- **Défense en profondeur réseau** : VNet flow logs + Traffic Analytics, Azure Virtual Network Manager (règles d'admin de sécurité, IPAM).
- **Multi-région** : dupliquer 30-connectivity pour une région secondaire (France South a des services limités et pas de zones de disponibilité : envisager une autre région européenne selon vos contraintes de souveraineté).

---

## 7. Points à valider avant production

Ce code n'a pas été exécuté contre un tenant ; il est conçu pour passer `terraform validate` mais doit être éprouvé dans un tenant de test.

| Point | Action |
|---|---|
| Versions `avm-ptn-alz` / provider `alz` / bibliothèque `platform/alz` | Vérifier la compatibilité dans les release notes, figer des versions exactes (`version = "x.y.z"`, `ref` de la bibliothèque). |
| Noms d'assignations ALZ modifiés (`Deploy-MDFC-Config-H224`, `Enable-DDoS-VNET`) | Vérifier qu'ils existent dans la version de bibliothèque choisie. |
| Clés de `policy_default_values` | Doivent correspondre à `alz_policy_default_values` de la bibliothèque. |
| Archétype `security` | Présent dans les versions récentes de la bibliothèque (MG Security ajouté en 2025). |
| Coûts | Pare-feu Premium, Bastion Standard, passerelle VPN, DDoS et ingestion Log Analytics/Sentinel représentent l'essentiel du coût fixe : estimer avec la calculatrice Azure avant déploiement. |
| Journaux Entra ID | Requiert le rôle Entra *Security Administrator* pour l'identité apply, ou un paramétrage manuel unique. |
