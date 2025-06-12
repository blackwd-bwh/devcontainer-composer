#!/bin/bash
set -euo pipefail

USER="blackwd-bwh"
PAT="${GITHUB_PAT:?You must export GITHUB_PAT}"

API_AUTH="Authorization: Bearer $PAT"
ACCEPT="Accept: application/vnd.github+json"

MANIFEST="manifest.json"
echo "📦 Building manifest for user: $USER"

# Get all user-published container packages
PACKAGES=$(curl -s -H "$API_AUTH" -H "$ACCEPT" \
  "https://api.github.com/users/$USER/packages?package_type=container")

declare -a FEATURES
declare -a TEMPLATES

for name in $(echo "$PACKAGES" | jq -r '.[].name'); do
  echo "🔍 Fetching tags for $name..."
  TAGS=$(curl -s -H "$API_AUTH" -H "$ACCEPT" \
    "https://api.github.com/users/$USER/packages/container/$name/versions" \
    | jq -r '.[].metadata.container.tags[]?' | sort -u)

  [[ -z "$TAGS" ]] && echo "⚠️  No tags found for $name, skipping..." && continue

  DEFAULT_TAG=$(echo "$TAGS" | grep -Fx latest || echo "$TAGS" | head -n1)

  if [[ "$name" == template-* || "$name" == *-base ]]; then
    ID="${name#template-}"
    ID="${ID%-base}"
    TEMPLATES+=("{\"id\":\"$ID\",\"ghcr\":\"ghcr.io/$USER/$name\",\"description\":\"$ID template\",\"defaultTag\":\"$DEFAULT_TAG\"}")
  else
    FEATURES+=("{\"id\":\"$name\",\"ghcr\":\"ghcr.io/$USER/$name\",\"description\":\"$name feature\",\"defaultTag\":\"$DEFAULT_TAG\"}")
  fi
done

# Write out the manifest
{
  echo '{'
  echo '  "features": ['
  (IFS=,; echo "    ${FEATURES[*]}")
  echo '  ],'
  echo '  "templates": ['
  (IFS=,; echo "    ${TEMPLATES[*]}")
  echo '  ]'
  echo '}'
} > "$MANIFEST"

echo "✅ Manifest written to: $MANIFEST"
