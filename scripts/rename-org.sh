#!/usr/bin/env bash
# Remplace le préfixe d'exemple "contoso" par celui de votre organisation
# dans la bibliothèque ALZ, les tfvars et les fichiers de configuration.
# Usage : ./scripts/rename-org.sh monorg "Mon Organisation"
set -euo pipefail

NEW_ORG="${1:?usage: $0 <org> [display-name]}"
NEW_DISPLAY="${2:-$NEW_ORG}"

if ! [[ "$NEW_ORG" =~ ^[a-z0-9]{2,10}$ ]]; then
  echo "Le préfixe doit contenir 2 à 10 caractères [a-z0-9]" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

files=$(grep -rl --exclude-dir=.git --exclude-dir=.terraform -e "contoso" -e "Contoso" "$ROOT" \
        | grep -v "scripts/rename-org.sh" || true)

for f in $files; do
  sed -i.bak \
    -e "s/display_name: Contoso$/display_name: ${NEW_DISPLAY}/" \
    -e "s/contoso/${NEW_ORG}/g" \
    -e "s/Contoso/${NEW_DISPLAY}/g" \
    "$f"
  rm -f "${f}.bak"
  echo "modifié : ${f#"$ROOT"/}"
done

echo "Terminé. Vérifiez les e-mails, équipes GitHub (CODEOWNERS) et noms de dépôts."
