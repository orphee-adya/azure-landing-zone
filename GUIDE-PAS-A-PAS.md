# Guide pas à pas — Landing zone Azure avec Terraform et GitHub Actions

Ce guide part de zéro. Il explique **ce que fait le projet**, **le vocabulaire**, **pourquoi il est découpé en « stages »**, puis **chaque action à faire, dans l'ordre**, avec ce qu'elle produit et comment vérifier qu'elle a marché. La dernière partie détaille chaque fichier.

---

## Sommaire

1. [Le projet en 30 secondes](#1-le-projet-en-30-secondes)
2. [Le vocabulaire indispensable](#2-le-vocabulaire-indispensable)
3. [Pourquoi des « stages » ?](#3-pourquoi-des--stages--)
4. [Ce que le projet va créer dans Azure](#4-ce-que-le-projet-va-créer-dans-azure)
5. [Prérequis](#5-prérequis)
6. [Lancer le projet pas à pas](#6-lancer-le-projet-pas-à-pas)
7. [Chaque stage expliqué en détail](#7-chaque-stage-expliqué-en-détail)
8. [Les pipelines GitHub expliqués](#8-les-pipelines-github-expliqués)
9. [Les autres fichiers du dépôt](#9-les-autres-fichiers-du-dépôt)
10. [Créer une souscription pour une équipe applicative](#10-créer-une-souscription-pour-une-équipe-applicative)
11. [Problèmes fréquents](#11-problèmes-fréquents)
12. [Coûts et mode « test »](#12-coûts-et-mode--test-)

---

## 1. Le projet en 30 secondes

Une **landing zone**, c'est le « terrain préparé » sur lequel les équipes vont ensuite déployer leurs applications dans Azure. Avant qu'une équipe crée sa première machine virtuelle, la landing zone a déjà mis en place :

- **l'organisation** : quelles souscriptions existent, et comment elles sont rangées ;
- **les règles de sécurité automatiques** : par exemple « pas de ressource hors de France » ou « pas d'IP publique sur une application interne » ;
- **la journalisation centralisée** : tous les journaux arrivent au même endroit ;
- **la sécurité** : Defender for Cloud, Sentinel (le SIEM, c'est-à-dire l'outil du SOC) et un coffre à secrets ;
- **le réseau central** : un pare-feu par lequel passe tout le trafic, un DNS privé et un accès d'administration sécurisé ;
- **une façon standard de livrer une souscription** à une équipe, déjà branchée sur tout ce qui précède.

Tout cela est décrit **en code (Terraform)** et déployé **automatiquement par GitHub Actions**. Personne ne clique dans le portail Azure, sauf pour quelques actions initiales.

---

## 2. Le vocabulaire indispensable

| Terme | Explication simple |
|---|---|
| **Tenant** (Entra ID) | Votre « annuaire » Microsoft : les utilisateurs, les groupes et les applications. Tout ce qui suit vit dans un tenant. |
| **Souscription** | Un « compte » Azure qui reçoit une facture. C'est aussi une frontière de sécurité : les droits donnés sur une souscription ne débordent pas sur une autre. |
| **Management group (MG)** | Un **dossier** qui contient des souscriptions (ou d'autres dossiers). Une règle ou un droit posé sur un dossier s'applique à tout ce qu'il contient. |
| **Resource group (RG)** | Un **tiroir** à l'intérieur d'une souscription, qui regroupe des ressources liées (par exemple tout le réseau central). |
| **Azure Policy** | Une **règle automatique**. Elle peut **refuser** (« interdit de créer une IP publique »), **auditer** (« signale les disques non chiffrés ») ou **corriger toute seule** (« si une VM n'envoie pas ses journaux, configure-la »). |
| **RBAC** | Qui a le droit de faire quoi, et où. Par exemple : le groupe « équipe réseau » est *Network Contributor* sur la souscription connectivity. |
| **Terraform** | Un outil qui lit des fichiers `.tf` décrivant l'infrastructure voulue, puis crée, modifie ou supprime les ressources pour que la réalité corresponde au code. |
| **`terraform plan`** | « Montre-moi ce que tu vas changer », sans rien toucher. |
| **`terraform apply`** | « Fais-le. » |
| **État (state)** | Un fichier où Terraform note ce qu'il a créé. Sans lui, il ne sait plus ce qui lui appartient. Ici, il est stocké dans un compte de stockage Azure sécurisé. |
| **Backend** | L'endroit où est rangé l'état : ici, le compte de stockage. |
| **Module** | Un bout de code Terraform réutilisable, comme une fonction. |
| **GitHub Actions** | Le moteur d'automatisation de GitHub : à chaque PR ou merge, il exécute des « workflows » (fichiers `.yml`). |
| **OIDC** | Le mécanisme qui permet à GitHub de **s'authentifier sur Azure sans mot de passe ni secret**. Azure fait confiance à un jeton signé par GitHub, et seulement s'il vient de *votre* dépôt et de *l'environnement* prévu. |
| **Environnement GitHub** | Une « porte » sur un workflow. L'environnement `alz-apply` impose qu'**un humain approuve** avant toute modification de l'infrastructure. |
| **Hub & spoke** | Une topologie réseau : un réseau central (**hub**) avec le pare-feu, auquel sont reliés les réseaux des applications (**spokes**), comme les rayons d'une roue. |
| **CAF / ALZ** | *Cloud Adoption Framework* / *Azure Landing Zones* : l'architecture de référence de Microsoft. Le projet la suit. |

---

## 3. Pourquoi des « stages » ?

« Stage » veut simplement dire **étape**. Le code n'est pas un seul gros bloc : il est découpé en **6 dossiers numérotés**, déployés **l'un après l'autre**, comme on construit une maison :

| Dossier | Analogie | Ce qu'il fait |
|---|---|---|
| `00-governance` | Le **cadastre et le règlement** | Crée les dossiers (management groups), range les souscriptions et pose les règles (policies) |
| `10-management` | Les **compteurs et caméras** | Crée l'endroit central où arrivent tous les journaux |
| `20-security` | Le **poste de garde** | Crée Sentinel pour le SOC et le coffre à secrets |
| `30-connectivity` | Les **routes et le portail d'entrée** | Crée le réseau central, le pare-feu et le DNS |
| `40-identity` | Le **bureau d'accueil** | Crée le réseau des contrôleurs de domaine (AD) |
| `50-subscription-vending` | Les **lotissements** | Livre des souscriptions prêtes à l'emploi aux équipes |

**Pourquoi ne pas tout mettre dans un seul dossier ?**

1. **Limiter les dégâts** : une erreur dans le code réseau ne peut pas casser les règles de sécurité, car ce sont deux fichiers d'état séparés.
2. **Des responsables différents** : l'équipe réseau valide `30-connectivity`, le SOC valide `20-security`, etc.
3. **La rapidité** : un `plan` sur un petit périmètre prend une minute au lieu de dix.
4. **L'ordre** : le réseau a besoin que les dossiers et les règles existent déjà, et les souscriptions applicatives ont besoin du réseau.

Chaque stage a **son propre fichier d'état** (`00-governance.tfstate`, `10-management.tfstate`…), rangé dans le même compte de stockage.

> Vous n'avez **jamais** à lancer ces stages à la main : la pipeline CD les déroule dans l'ordre. Vous approuvez simplement chaque étape dans GitHub.

**Le « bootstrap »** est une étape **à part**, lancée **une seule fois depuis votre poste**. C'est l'œuf avant la poule : la pipeline a besoin d'un endroit où stocker l'état et d'une identité pour se connecter à Azure, et c'est le bootstrap qui les crée.

---

## 4. Ce que le projet va créer dans Azure

### Les dossiers (management groups)

```
Tenant Root Group                     (existe déjà, on n'y touche pas)
└── contoso                           ← votre "racine" (créée par le bootstrap)
    ├── contoso-platform              ← tout ce que gère l'équipe plateforme
    │   ├── contoso-management        → contient la souscription "management"
    │   ├── contoso-connectivity      → contient la souscription "connectivity"
    │   ├── contoso-identity          → contient la souscription "identity"
    │   └── contoso-security          → contient la souscription "security"
    ├── contoso-landingzones          ← les applications
    │   ├── contoso-corp              → applis internes (aucune exposition Internet)
    │   └── contoso-online            → applis exposées sur Internet
    ├── contoso-sandbox               → bacs à sable isolés pour tester
    └── contoso-decommissioned        → souscriptions en fin de vie
```

« contoso » sera remplacé par le nom de votre organisation (étape 6.2).

### Les 4 souscriptions « plateforme » et leur contenu

| Souscription | Rôle | Contenu principal |
|---|---|---|
| **management** | Exploitation | Stockage de l'état Terraform · identités de la pipeline · **Log Analytics** (journaux centraux) · stockage d'archive des journaux · alertes |
| **security** | SOC | **Microsoft Sentinel** · journaux Entra ID (option) · **Key Vault** |
| **connectivity** | Réseau | Réseau **hub** · **Azure Firewall** · **Bastion** (accès RDP/SSH sécurisé) · **zones DNS privées** · DNS Resolver · VPN (option) |
| **identity** | Annuaire | Réseau pour les contrôleurs de domaine Active Directory |

Puis **une souscription par application et par environnement**, livrée à la demande par le stage 50.

---

## 5. Prérequis

### Sur votre poste

| Outil | Pourquoi | Vérification |
|---|---|---|
| **Terraform ≥ 1.9** | Exécuter le bootstrap | `terraform version` |
| **Azure CLI** | Se connecter à Azure | `az version` |
| **GitHub CLI** (`gh`) | Fournir un jeton GitHub à Terraform | `gh --version` |
| **git** | Pousser le code | `git --version` |

Sous Windows, utilisez **WSL** ou **Git Bash** : les commandes du guide sont en bash.

### Côté Azure

- [ ] Un compte **Global Administrator** du tenant, uniquement pour le bootstrap.
- [ ] **4 souscriptions vides** déjà créées (management, connectivity, identity, security), dont vous notez les **IDs**. Vous pouvez les créer depuis le portail (*Souscriptions > Ajouter*) ou via votre contrat EA/MCA.
- [ ] Des **groupes Entra ID** pour les droits (admins plateforme, réseau, SOC, lecteurs). Vous pouvez les créer plus tard.

### Côté GitHub

- [ ] Une **organisation GitHub**. Les équipes d'approbateurs n'existent que dans une organisation, pas sur un compte personnel.
- [ ] Un **dépôt vide**, par exemple `azure-landing-zone`, sur lequel vous êtes **administrateur**.
- [ ] Une **équipe** GitHub d'approbateurs, par exemple `cloud-platform-approvers`, avec au moins vous dedans.

---

## 6. Lancer le projet pas à pas

### Étape 6.1 — Décompresser le projet et l'initialiser avec git

```bash
unzip azure-landing-zone.zip
cd azure-landing-zone
git init -b main
```

### Étape 6.2 — Remplacer « contoso » par le nom de votre organisation

```bash
./scripts/rename-org.sh monorg "Mon Organisation"
```

- `monorg` : 2 à 10 caractères, minuscules et chiffres uniquement. Il apparaît dans **tous** les noms de ressources (par exemple `rg-monorg-hub-frc`).
- Le script remplace « contoso » partout : noms des dossiers Azure, fichiers de configuration, CODEOWNERS.

**Vérification** : `grep -ri contoso .` ne doit plus rien renvoyer, ou seulement des commentaires.

### Étape 6.3 — Remplir la configuration commune

Ouvrez `config/common.tfvars`. Ce fichier est lu par **tous** les stages :

```hcl
org            = "monorg"          # le préfixe choisi à l'étape 6.2
location       = "francecentral"   # région principale
location_short = "frc"             # abréviation utilisée dans les noms

subscription_ids = {               # les IDs de vos 4 souscriptions
  management   = "xxxxxxxx-..."
  connectivity = "xxxxxxxx-..."
  identity     = "xxxxxxxx-..."
  security     = "xxxxxxxx-..."
}

tfstate = {                        # où est rangé l'état (créé à l'étape 6.5)
  subscription_id      = "<ID de la souscription management>"
  resource_group_name  = "rg-monorg-tfstate-frc"
  storage_account_name = "stmonorgtfstatefrc"
  container_name       = "tfstate"
}

platform_contact_email = "cloud@monorg.fr"   # reçoit les alertes
tags = { ... }                               # étiquettes posées sur toutes les ressources
```

Pour retrouver les IDs de souscriptions : `az account list -o table`.

> **Attention** : le nom du compte de stockage (`stmonorgtfstatefrc`) doit être **unique au monde**. S'il est déjà pris, le bootstrap échouera : choisissez-en un autre (3 à 24 caractères, minuscules et chiffres), puis reportez-le ici **et** dans `state_storage_account_name` du bootstrap.

### Étape 6.4 — Se donner temporairement les droits nécessaires

Le bootstrap doit créer un dossier sous la racine du tenant et donner des droits à la pipeline. Il faut donc, **temporairement**, des droits très élevés :

1. Portail Azure > **Microsoft Entra ID** > **Propriétés** > « *Gestion de l'accès pour les ressources Azure* » = **Oui**, puis **Enregistrer**. C'est ce qu'on appelle l'*elevate access*.
2. Dans un terminal :

```bash
az login --tenant <ID-du-tenant>
TENANT_ID=$(az account show --query tenantId -o tsv)
ME=$(az ad signed-in-user show --query id -o tsv)

# Owner sur la racine du tenant (TEMPORAIRE — retiré à l'étape 6.8)
az role assignment create --assignee "$ME" --role Owner \
  --scope "/providers/Microsoft.Management/managementGroups/$TENANT_ID"
```

Attendez **5 minutes** que les droits se propagent, puis faites `az logout && az login` pour rafraîchir le jeton.

### Étape 6.5 — Lancer le bootstrap

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
```

Éditez `bootstrap/terraform.tfvars` :

| Variable | Quoi mettre |
|---|---|
| `org`, `org_display_name` | Même préfixe qu'à l'étape 6.2, et le nom affiché |
| `subscription_ids` | Les 4 IDs (identiques à `common.tfvars`) |
| `github_owner` | Le nom de votre **organisation** GitHub |
| `github_repository` | Le nom du dépôt (sans l'organisation) |
| `github_apply_reviewer_teams` | Le *slug* de l'équipe d'approbateurs |
| `github_prevent_self_review` | `false` si vous êtes **seul** à tester (sinon vous ne pourrez pas approuver vos propres déploiements) |

Ce fichier n'est **pas** envoyé sur GitHub : il est ignoré via `.gitignore`.

Puis lancez :

```bash
gh auth login                       # une seule fois : connectez-vous à GitHub
export GITHUB_TOKEN=$(gh auth token)

terraform init
terraform plan                      # relisez : environ 30 ressources à créer
terraform apply                     # tapez "yes"
```

**Ce que le bootstrap vient de créer :**

| Élément | À quoi ça sert |
|---|---|
| Management group `monorg` | La racine de votre organisation dans Azure |
| RG `rg-monorg-tfstate-frc` + compte de stockage | **L'endroit où sont rangés les fichiers d'état**. Il est durci : accès par Entra ID uniquement (pas de clé), historique des versions, corbeille de 30 jours, verrou anti-suppression. |
| RG `rg-monorg-cicd-frc` + 2 **identités managées** | Les « comptes de service » de la pipeline : **`plan`** en lecture seule, **`apply`** pour modifier |
| **Fédérations OIDC** | Elles disent à Azure : « fais confiance aux jetons GitHub du dépôt X, mais seulement depuis l'environnement Y ». Aucun mot de passe. |
| **Droits (RBAC)** | `plan` = *Reader* ; `apply` = *Owner* sur votre racine ; vous-même = accès au stockage de l'état |
| Environnements GitHub `alz-plan` et `alz-apply` | `alz-apply` exige l'**approbation** de l'équipe désignée, et uniquement depuis `main` |
| Variables GitHub | Les IDs dont la pipeline a besoin (tenant, stockage, identités). Ce ne sont **pas** des secrets. |

**Vérification :**
- Portail Azure > *Management groups* : `monorg` apparaît.
- GitHub > dépôt > *Settings > Environments* : `alz-plan` et `alz-apply` existent.
- GitHub > *Settings > Secrets and variables > Actions > Variables* : `AZURE_TENANT_ID`, `TFSTATE_...` sont présents.

### Étape 6.6 — Ranger l'état du bootstrap dans Azure

Pour l'instant, l'état du bootstrap est un fichier local (`terraform.tfstate`). On le déplace dans le stockage qu'on vient de créer, pour ne pas le perdre.

1. Ouvrez `bootstrap/versions.tf` et **décommentez** le bloc `backend "azurerm"` (retirez les `#`) en remplaçant les valeurs par les vôtres :

```hcl
  backend "azurerm" {
    subscription_id      = "<ID souscription management>"
    resource_group_name  = "rg-monorg-tfstate-frc"
    storage_account_name = "stmonorgtfstatefrc"
    container_name       = "tfstate"
    key                  = "bootstrap.tfstate"
    use_azuread_auth     = true
  }
```

2. Lancez :

```bash
terraform init -migrate-state      # répondez "yes"
rm -f terraform.tfstate terraform.tfstate.backup
cd ..
```

**Vérification** : dans le portail, le conteneur `tfstate` du compte de stockage contient `bootstrap.tfstate`.

### Étape 6.7 — Adapter les paramètres de chaque stage (optionnel au début)

Chaque dossier `stages/XX-.../terraform.tfvars` contient les réglages propres à ce stage. Les valeurs par défaut fonctionnent. Points à regarder :

| Fichier | Réglage | Valeur par défaut |
|---|---|---|
| `00-governance/terraform.tfvars` | `allowed_locations` : régions autorisées | France Central, France South, West Europe |
| | `rbac_assignments` : droits de vos groupes Entra | vide (à remplir plus tard) |
| `10-management/terraform.tfvars` | `law_retention_days` : conservation des journaux | 90 jours |
| `30-connectivity/terraform.tfvars` | `firewall_sku_tier` | `Premium` (voir §12 pour réduire les coûts) |
| | `vpn_gateway_enabled` | `false` (passer à `true` si vous avez un site on-premise) |
| | plan d'adressage IP | hub `10.0.0.0/22` (à aligner avec votre réseau existant !) |

> **Le plan d'adressage IP est le seul choix difficile à changer après coup.** Vérifiez avec votre équipe réseau que `10.0.0.0/22` (hub), `10.0.4.0/24` (identité) et `10.1.0.0/16` (applications) ne chevauchent pas vos réseaux on-premise.

### Étape 6.8 — Retirer les droits temporaires

```bash
az role assignment delete --assignee "$ME" --role Owner \
  --scope "/providers/Microsoft.Management/managementGroups/$TENANT_ID"
```

Puis, dans le portail Entra ID > *Propriétés*, remettez « *Gestion de l'accès pour les ressources Azure* » sur **Non**.

À partir d'ici, **seule la pipeline modifie l'infrastructure**.

### Étape 6.9 — Générer les fichiers de verrouillage des versions

Ces fichiers (`.terraform.lock.hcl`) garantissent que la pipeline utilise **exactement** les mêmes versions de plugins Terraform à chaque exécution.

```bash
for d in stages/*/; do
  (cd "$d" && terraform init -backend=false && \
   terraform providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=windows_amd64)
done
```

### Étape 6.10 — Pousser le code sur GitHub

```bash
git add .
git commit -m "Landing zone initiale"
git remote add origin https://github.com/<organisation>/<depot>.git
git push -u origin main
```

Ce `push` sur `main` **déclenche automatiquement le premier déploiement** (étape suivante).

### Étape 6.11 — Suivre et approuver le premier déploiement

1. GitHub > onglet **Actions** > workflow **CD**.
2. Le premier stage (`00-governance`) lance son **plan**. Cliquez sur le run, puis sur le job `plan · 00-governance` : le **résumé** affiche ce qui va être créé.
3. Un bandeau jaune **« Review deployments »** apparaît. Relisez le plan, cochez `alz-apply`, puis cliquez sur **Approve and deploy**.
4. L'`apply` s'exécute. Le stage suivant démarre alors, et ainsi de suite.

**Ordre et durées indicatives :**

```
00-governance      (~10-15 min : ~150 policies et rôles)
   ↓
10-management      (~3 min)
   ↓
20-security ───────── en parallèle ────── 30-connectivity (~20-30 min : pare-feu, Bastion)
                                              ↓
                              40-identity (~3 min)    50-subscription-vending (rien au début)
```

**Vérifications après déploiement :**
- *Management groups* : toute l'arborescence est visible et chaque souscription est rangée dans son dossier.
- *Policy > Assignments* (sur `monorg`) : les règles ALZ sont présentes.
- Souscription connectivity : le pare-feu, le Bastion et environ 30 zones DNS `privatelink.*` existent.
- Souscription security : *Microsoft Sentinel* est activé sur `law-monorg-sentinel-frc`.

### Étape 6.12 — Protéger la branche `main`

GitHub > *Settings > Rules > Rulesets > New branch ruleset*, ciblé sur `main` :

- ✅ *Require a pull request before merging* (1 ou 2 approbations)
- ✅ *Require review from Code Owners*
- ✅ *Require status checks to pass* : ajoutez `fmt · validate · tflint · checkov` et les jobs `plan`
- ✅ *Block force pushes*

Désormais, **tout changement passe par une Pull Request** : la CI montre le plan dans la PR, un relecteur valide, on merge, puis la CD déploie après approbation.

### Étape 6.13 — Lancer la correction des ressources existantes (si besoin)

Les règles qui « corrigent toutes seules » ne s'appliquent automatiquement qu'aux **nouvelles** ressources. Si les souscriptions contenaient déjà des ressources : portail > *Policy* > *Remediation* > lancez une tâche pour chaque règle non conforme.

### Le cycle de travail au quotidien

```
1. git checkout -b ma-modif
2. Modifier un fichier .tf ou .tfvars
3. git push + ouvrir une Pull Request
4. La CI vérifie le code et commente le plan de chaque stage dans la PR
5. Un relecteur (CODEOWNERS) approuve, puis on merge
6. La CD rejoue les stages : ceux qui ont des changements demandent une approbation
7. Approuver, et c'est déployé
```

---

## 7. Chaque stage expliqué en détail

Chaque dossier de stage contient toujours :

| Fichier | Rôle |
|---|---|
| `versions.tf` | Version de Terraform et des plugins, souscription ciblée, backend (rempli par la pipeline) |
| `variables.common.tf` | Déclaration des variables communes (**identique** dans tous les stages, valeurs dans `config/common.tfvars`) |
| `variables.tf` | Déclaration des variables propres au stage |
| `terraform.tfvars` | **Vos valeurs** pour ces variables |
| `main.tf` (+ autres `.tf`) | Les ressources à créer |
| `outputs.tf` | Les informations exposées aux autres stages (par exemple l'IP du pare-feu) |

### 7.0 Le module `modules/conventions` (utilisé partout)

C'est le **dictionnaire des noms**. À partir de `org` et `location_short`, il calcule le nom de toutes les ressources selon la convention Microsoft (CAF), par exemple :
- `rg-monorg-hub-frc` (resource group du hub)
- `law-monorg-platform-frc` (Log Analytics)
- `afw-monorg-hub-frc` (pare-feu)

Il calcule aussi les **identifiants Azure à l'avance**. C'est ce qui permet au stage 00 de dire aux règles « envoie les journaux vers le workspace X » **avant même** que le stage 10 ait créé X : les règles se mettront à fonctionner dès que X existera.

### 7.1 `00-governance` — Organisation et règles

**Ce qu'il crée :**

1. **L'arborescence des management groups** (voir §4). Elle est décrite dans `lib/architecture_definitions/landing_zone.alz_architecture_definition.yaml`.
2. **Les règles Azure Policy officielles de Microsoft (ALZ)**, posées sur chaque dossier, via le module Microsoft `Azure/avm-ptn-alz/azurerm`. La version de la bibliothèque de règles est figée dans `lib/alz_library_metadata.json`. Exemples :
   - **Sur la racine** : active Defender for Cloud sur tous les types de ressources, envoie les journaux d'activité de toutes les souscriptions vers Log Analytics, installe l'agent de supervision (AMA) sur les VM, applique le référentiel de sécurité Microsoft (MCSB).
   - **Sur Landing Zones** : interdit d'ouvrir RDP/SSH sur Internet, impose un NSG sur chaque sous-réseau, impose HTTPS/TLS, configure les sauvegardes.
   - **Sur Corp** : **interdit les IP publiques** et les accès publics aux services PaaS, et enregistre automatiquement les private endpoints dans le DNS privé.
   - **Sur Sandbox** : interdit de relier le réseau au reste de l'entreprise.
   - **Sur Decommissioned** : interdit de créer quoi que ce soit.
3. **Le rangement des 4 souscriptions plateforme** dans leurs dossiers.
4. **Deux règles ajoutées** : les **régions autorisées** (souveraineté des données), pour les ressources et pour les resource groups.
5. **Les droits de vos équipes** (`rbac_assignments`), toujours donnés à des **groupes**, jamais à des personnes.

**Bloc `policy_default_values`** : il fournit aux règles Microsoft les informations propres à votre installation (quel workspace reçoit les journaux, où sont les zones DNS…).

**Bloc `policy_assignments_to_modify`** : il ajuste deux règles. Il renseigne l'e-mail de contact de Defender, et désactive l'obligation de protection DDoS si vous n'avez pas pris l'option DDoS.

### 7.2 `10-management` — Journalisation centrale

| Ressource | Explication |
|---|---|
| RG `rg-monorg-management-frc` | Le tiroir |
| **Log Analytics** `law-monorg-platform-frc` | **La base centrale des journaux** : journaux d'activité de toutes les souscriptions, diagnostics, performances des VM, journaux du pare-feu. Conservation de 90 jours, avec un verrou anti-suppression. |
| **Identité AMA** | L'identité qu'utilisent les agents de supervision installés sur les VM pour envoyer leurs données |
| **3 Data Collection Rules (DCR)** | Ce que les agents collectent : **VM Insights** (CPU, mémoire, disque), **Change Tracking** (logiciels installés, services, fichiers modifiés), **Defender for SQL** |
| **Compte de stockage d'archive** | Une copie des journaux d'activité conservée **3 ans** (paramétrable), sur un stockage **immuable** (WORM : impossible à modifier ou supprimer) qui passe automatiquement en stockage froid puis archive pour réduire le coût. Utile pour l'audit et la conformité. |
| **Export continu** | Copie en permanence la table `AzureActivity` vers l'archive |
| **Action group** | « Qui prévenir » : l'e-mail de l'équipe plateforme |
| **Alerte Service Health** | Vous prévient des incidents et maintenances Azure dans vos régions |

### 7.3 `20-security` — Le poste de garde du SOC

| Ressource | Explication |
|---|---|
| RG `rg-monorg-security-frc` | Le tiroir |
| **Log Analytics** `law-monorg-sentinel-frc` | Un workspace **séparé** de celui de l'exploitation : le SOC le gère seul. L'exploitation n'y a pas accès, et inversement. |
| **Microsoft Sentinel** | Le SIEM, activé sur ce workspace |
| **Règle d'incidents Defender** | Chaque alerte Defender for Cloud de gravité moyenne ou haute crée automatiquement un **incident** dans Sentinel |
| **Journaux Entra ID** (option, `entra_diagnostics_enabled`) | Connexions, connexions à risque, audit de l'annuaire, envoyés vers Sentinel. Désactivé par défaut, car il faut un rôle Entra supplémentaire pour la pipeline. |
| **Key Vault Premium** | Le coffre pour les secrets de la plateforme (clé VPN partagée, certificats). Accès par RBAC, **protection contre la purge**, aucun accès réseau public par défaut, journaux envoyés vers Sentinel. |

### 7.4 `30-connectivity` — Le réseau central

Il est réparti en trois fichiers :

**`main.tf` :**

| Ressource | Explication |
|---|---|
| VNet **hub** `10.0.0.0/22` | Le réseau central |
| 3 sous-réseaux aux noms imposés par Azure | `AzureFirewallSubnet`, `GatewaySubnet` (VPN), `AzureBastionSubnet` |
| **Bastion** (Standard) | Pour se connecter en RDP/SSH aux VM **sans leur donner d'IP publique**, depuis le portail ou `az network bastion ssh` |
| **Passerelle VPN** (option) | Relie Azure à vos bureaux ou datacenters. Son déploiement prend 30 à 45 minutes. |
| **Table de routage de la passerelle** | Force le trafic qui vient d'on-premise à passer par le pare-feu |
| **Plan DDoS** (option) | Protection anti-DDoS renforcée (coûteuse) |

**`firewall.tf` :**

| Ressource | Explication |
|---|---|
| **Azure Firewall Premium** | Réparti sur 3 zones de disponibilité. **Tout trafic** sortant des applications ou circulant entre elles passe par lui. Par défaut, **tout est refusé**. |
| **Firewall policy** | Bloque les adresses malveillantes connues (*threat intelligence*), détecte et bloque les intrusions (**IDPS**), sert de **proxy DNS** |
| **Règles « plateforme »** | Les seuls flux autorisés au départ : Active Directory vers le réseau identité, activation Windows (KMS), Windows Update, envoi des journaux vers Azure Monitor |
| **Diagnostics** | Tous les journaux du pare-feu sont envoyés vers Log Analytics |

Les équipes applicatives ajouteront leurs propres règles plus tard, par Pull Request relue par l'équipe réseau.

**`dns.tf` :**

| Ressource | Explication |
|---|---|
| RG `rg-monorg-dns-frc` | Le tiroir DNS |
| **~30 zones DNS privées `privatelink.*`** | Quand une application crée un *private endpoint* (accès privé à un stockage, une base SQL…), son nom doit se résoudre vers une IP privée. Ces zones sont centralisées ici, et la règle ALZ du dossier Corp y crée les enregistrements automatiquement. |
| **DNS Private Resolver** | Permet aux serveurs on-premise de résoudre les noms privés Azure (*inbound*) et, si vous le configurez, à Azure de résoudre vos domaines on-premise (*outbound* + `dns_forwarding_rules`) |

**Le chemin du DNS** : VM d'une application → pare-feu (proxy DNS) → DNS Azure, qui connaît les zones privées liées au hub.

### 7.5 `40-identity` — Réseau des contrôleurs de domaine

Il utilise le module `modules/spoke-network` pour créer :
- un VNet `10.0.4.0/24`, relié au hub par un **peering** dans les deux sens ;
- un sous-réseau `domain-controllers` avec un **NSG** qui autorise uniquement les ports Active Directory depuis le réseau interne, plus RDP/SSH depuis Bastion, et refuse tout le reste ;
- une route `0.0.0.0/0` vers le pare-feu, pour que les contrôleurs de domaine sortent eux aussi par le pare-feu.

Les VM des contrôleurs de domaine ne sont **pas** créées ici : elles relèvent de l'équipe identité.

Pour connaître l'IP du pare-feu, ce stage **lit l'état du stage 30** (`terraform_remote_state`). C'est pour cette raison que le stage 30 doit passer avant.

### 7.6 `50-subscription-vending` — Livrer des souscriptions aux équipes

C'est le « distributeur » de souscriptions. **Chaque fichier YAML** placé dans `landing-zones/` correspond à une souscription livrée, avec :

1. la **souscription** elle-même, créée (EA/MCA) ou adoptée si elle existe déjà ;
2. son **rangement** dans le bon dossier (Corp, Online ou Sandbox), qui lui applique automatiquement toutes les règles ;
3. son **réseau** : VNet relié au hub, route vers le pare-feu, NSG sur chaque sous-réseau, DNS vers le pare-feu. Une sandbox n'est **jamais** reliée au hub.
4. les **droits** du groupe Entra de l'équipe ;
5. une **identité pour la pipeline de l'équipe**, qui pourra déployer son application depuis **son propre dépôt GitHub**, sans secret ;
6. un **budget** avec des alertes à 80 % (réel) et 100 % (prévisionnel).

**Au premier déploiement, ce dossier est vide : rien n'est créé.** Deux exemples sont fournis dans `examples/` (voir §10).

---

## 8. Les pipelines GitHub expliqués

Il y a 4 fichiers dans `.github/workflows/`.

### 8.1 `terraform-stage.yml` — La brique réutilisable

Ce workflow n'est jamais lancé seul : les autres l'appellent pour **un** stage donné. Il contient 2 jobs.

**Job `plan`** (environnement `alz-plan`, identité en **lecture seule**) :
1. Récupère le code.
2. Installe Terraform.
3. `terraform init` : se connecte au stockage de l'état, avec le fichier `<stage>.tfstate`.
4. `terraform plan -detailed-exitcode -out=tfplan` : calcule les changements. Le code de sortie indique **s'il y a des changements** (0 = aucun, 2 = des changements, 1 = erreur).
5. Écrit le plan dans le **résumé du run**.
6. Si on est dans une PR, **publie ou met à jour un commentaire** contenant le plan.
7. Si un apply est prévu et qu'il y a des changements, **sauvegarde le fichier de plan**.

**Job `apply`** (environnement `alz-apply`, identité qui **peut modifier**) :
- Il démarre **uniquement si** un apply est demandé **et** qu'il y a des changements.
- **GitHub met le job en pause jusqu'à l'approbation** d'un membre de l'équipe désignée.
- Il récupère **exactement le plan qui a été relu**, puis l'applique. Si quelque chose a changé entre-temps, Terraform refuse : on n'applique jamais un plan différent de celui qui a été approuvé.

**Pourquoi deux identités ?** Grâce à la fédération OIDC, l'identité `apply` (*Owner*) ne peut être obtenue **que** par un job qui déclare `environment: alz-apply`. Ce job exige une approbation humaine et ne tourne que depuis `main`. Une PR malveillante ne peut donc rien modifier.

### 8.2 `ci.yml` — Les vérifications sur chaque Pull Request

Il se déclenche à l'ouverture ou à la mise à jour d'une PR vers `main`.

**Job `static-analysis`** :

| Étape | Ce qu'elle vérifie |
|---|---|
| `terraform fmt -check` | Le code est correctement formaté |
| `terraform validate` | La syntaxe est valide, dans chaque dossier |
| **tflint** | Les erreurs fréquentes et les mauvaises pratiques Azure (type de VM inexistant, etc.) |
| **Checkov** | Les problèmes de **sécurité** dans le code (stockage public, TLS faible…). Les résultats apparaissent dans l'onglet **Security** de GitHub. |

**Job `plan`** : appelle `terraform-stage.yml` pour les 6 stages **en parallèle**, en plan seulement. Chaque plan est commenté dans la PR.

### 8.3 `cd.yml` — Le déploiement sur `main`

Il se déclenche après un merge sur `main`, ou à la main (*Run workflow*). Il appelle `terraform-stage.yml` avec apply activé, **dans l'ordre** :

```
governance → management → security ─────────┐
                        → connectivity → identity
                                       → vending (attend aussi security)
```

- `if: !failure() && !cancelled()` : un stage **sans changement** est sauté mais **ne bloque pas** les suivants. Un stage **en échec** bloque la suite.
- `concurrency: alz-cd` : **un seul déploiement à la fois**, et on n'interrompt jamais un déploiement en cours.

### 8.4 `drift-detection.yml` — Détecter les modifications faites à la main

Il tourne **chaque jour ouvré à 6h17** (heure de Paris en hiver) et lance un `plan` sur chaque stage. Si un plan montre des différences, c'est que quelqu'un a modifié Azure **hors de Terraform** (dans le portail, par exemple). Le workflow **ouvre une issue GitHub « Drift détecté : <stage> »** contenant le détail, ou la complète si elle existe déjà.

Il faut alors, soit reporter la modification dans le code, soit relancer la CD pour l'annuler.

---

## 9. Les autres fichiers du dépôt

| Fichier | Rôle |
|---|---|
| `README.md` | La documentation d'architecture (version courte et technique) |
| `GUIDE-PAS-A-PAS.md` | Ce guide |
| `config/common.tfvars` | Les valeurs partagées par tous les stages |
| `bootstrap/` | L'étape initiale lancée à la main (voir 6.5) : `main.tf` (Azure), `github.tf` (environnements et variables GitHub), `variables.tf`, `outputs.tf`, `terraform.tfvars.example` |
| `modules/conventions/` | Le dictionnaire des noms et identifiants (§7.0) |
| `modules/spoke-network/` | Crée un réseau d'application relié au hub (utilisé par 40-identity) |
| `modules/landing-zone/` | Crée une souscription complète pour une équipe (utilisé par 50) |
| `scripts/rename-org.sh` | Remplace « contoso » par votre préfixe |
| `.tflint.hcl` | La configuration de tflint |
| `.checkov.yaml` | La configuration de Checkov, avec la **liste des exceptions justifiées** (par exemple, le stockage de l'état est accessible depuis Internet pour que les runners GitHub puissent l'atteindre, mais uniquement avec une authentification Entra ID) |
| `.pre-commit-config.yaml` | Les mêmes vérifications **sur votre poste** avant chaque commit (`pip install pre-commit && pre-commit install`). Inclut **gitleaks**, qui bloque un commit contenant un secret. |
| `.gitignore` | Les fichiers à ne jamais envoyer : états locaux, plans, `bootstrap/terraform.tfvars` |
| `.github/CODEOWNERS` | **Qui doit relire quoi** : réseau pour `30-connectivity`, SOC pour `20-security`, etc. |
| `.github/dependabot.yml` | Ouvre chaque semaine une PR pour mettre à jour les plugins Terraform et les actions GitHub |
| `.github/pull_request_template.md` | La checklist affichée à chaque nouvelle PR |
| `.github/ISSUE_TEMPLATE/landing-zone-request.yml` | Un **formulaire** grâce auquel une équipe demande une nouvelle souscription |

---

## 10. Créer une souscription pour une équipe applicative

1. L'équipe remplit le formulaire **« Demande de landing zone »** (onglet *Issues* > *New issue*).
2. Copiez un exemple :
   ```bash
   cp stages/50-subscription-vending/examples/app1-prod.yaml \
      stages/50-subscription-vending/landing-zones/app2-prod.yaml
   ```
3. Éditez le fichier :

```yaml
archetype: corp                  # corp (interne) | online (exposée Internet) | sandbox (isolée)

subscription:
  display_name: "Monorg - App2 - Production"
  workload: Production           # ou DevTest (tarifs réduits)
  # existing_id: "xxxx-..."      # décommenter pour ADOPTER une souscription existante

network:
  address_space: ["10.1.1.0/24"] # une plage LIBRE, à noter dans votre tableau d'adressage
  subnets:
    app:  { address_prefix: "10.1.1.0/26" }
    data: { address_prefix: "10.1.1.64/26" }
    pe:   { address_prefix: "10.1.1.128/27" }   # pour les private endpoints

role_assignments:
  app2-devops:
    principal_id: "<object ID du groupe Entra de l'équipe>"
    role_definition_name: "Contributor"

github_oidc:                     # la pipeline de l'équipe pourra déployer sans secret
  repository: "monorg/app2"
  environment: "production"

budget:
  amount: 2000                   # euros par mois
  contact_emails: ["owner-app2@monorg.fr"]
```

4. **Créer une nouvelle souscription** (plutôt qu'en adopter une existante) demande deux choses :
   - renseigner `billing_scope_id` dans `stages/50-subscription-vending/terraform.tfvars`, c'est-à-dire l'identifiant de votre compte de facturation EA ou MCA ;
   - qu'un administrateur de la facturation donne le rôle de **créateur de souscriptions** à l'identité `id-monorg-alz-apply-frc`.

   Sinon, créez la souscription dans le portail et utilisez `existing_id`.
5. Ouvrez une PR. Les équipes réseau et FinOps relisent, puis vous mergez et approuvez.
6. Récupérez l'identifiant à transmettre à l'équipe (`cicd_client_id`) dans la sortie du stage 50. L'équipe le configure comme `AZURE_CLIENT_ID` dans son dépôt.

**Pour retirer une souscription** : passez `archetype: decommissioned`. **Ne supprimez pas le fichier**, car cela annulerait la souscription. Le code l'empêche d'ailleurs (`prevent_destroy`).

---

## 11. Problèmes fréquents

| Symptôme | Cause probable | Solution |
|---|---|---|
| Bootstrap : `AuthorizationFailed` sur le management group | Droits pas encore propagés | Attendre 5 à 10 minutes après l'étape 6.4, puis `az logout && az login` |
| Bootstrap : `StorageAccountAlreadyTaken` | Nom du stockage déjà pris dans le monde | Renseigner `state_storage_account_name` avec un autre nom, et le reporter dans `common.tfvars` |
| Bootstrap : erreur GitHub `404` sur l'équipe | Mauvais slug d'équipe, ou dépôt hors organisation | Vérifier le slug dans l'URL de l'équipe, ou mettre `manage_github = false` et créer les environnements à la main |
| `-migrate-state` : `403 AuthorizationPermissionMismatch` | Le droit sur le stockage n'est pas encore propagé | Attendre 5 minutes et relancer |
| Pipeline : `AADSTS700213: No matching federated identity record` | Le nom du dépôt, de l'organisation ou de l'environnement ne correspond pas à la fédération | Vérifier `github_owner` et `github_repository` du bootstrap (attention à la casse) |
| Pipeline : impossible d'approuver soi-même | `prevent_self_review = true` | Faire approuver par un collègue, ou repasser le bootstrap avec `github_prevent_self_review = false` |
| PR : les plans de 40 et 50 échouent tout au début | L'état du stage 30 n'existe pas encore | C'est normal avant le tout premier déploiement complet |
| Stage 00 : erreur sur `Deploy-MDFC-Config-H224` ou `Enable-DDoS-VNET` | Le nom de la règle a changé dans la version de la bibliothèque ALZ | Rechercher le nom exact dans la bibliothèque correspondant à la version figée et l'ajuster dans `00-governance/main.tf` |
| Création de ressource refusée : `RequestDisallowedByPolicy` | Une règle ALZ bloque l'action, et c'est voulu | Lire le message : il nomme la règle. Corriger la ressource, ou demander une exception (*exemption*) |
| Issue « Drift détecté » | Modification faite dans le portail | Reporter la modification dans le code, ou relancer la CD |

---

## 12. Coûts et mode « test »

L'essentiel du coût **fixe** vient de quelques ressources. Les ordres de grandeur ci-dessous sont **à vérifier** dans la [calculatrice Azure](https://azure.microsoft.com/pricing/calculator/) pour votre région :

| Ressource | Ordre de grandeur |
|---|---|
| Azure Firewall **Premium** | Le plus gros poste : au-delà de 1 000 €/mois. La version Standard coûte environ 30 % de moins. |
| Bastion Standard | Quelques centaines d'euros par mois |
| Passerelle VPN (option) | Quelques centaines d'euros par mois |
| Plan DDoS (option) | Environ 2 500 à 3 000 €/mois : à réserver aux applications exposées critiques |
| Log Analytics / Sentinel | Selon le volume de journaux ingérés (facturé au Go) |

**Pour un premier essai dans un tenant de test**, dans `stages/30-connectivity/terraform.tfvars` :

```hcl
firewall_sku_tier       = "Standard"
bastion_enabled         = false
vpn_gateway_enabled     = false
ddos_protection_enabled = false
```

Vous pourrez repasser en Premium plus tard par une simple PR.

**Pour tout supprimer après un test** : il faut le faire dans l'ordre inverse (50 → 40 → 30 → 20 → 10 → 00 → bootstrap), en local, avec `terraform destroy`, après avoir retiré les verrous anti-suppression (*Locks*). C'est volontairement contraignant : en production, on ne détruit jamais une landing zone.
