#!/bin/bash
set -euo pipefail

# ===============================================
# USAGE: ./discover_github_feature.sh <github-account> [branch]
# EXAMPLE: ./discover_github_feature.sh blackwd-bwh
# ===============================================

ACCOUNT="${1:-}"
BRANCH="${2:-main}"

if [[ -z "$ACCOUNT" ]]; then
  echo "Usage: $0 <github-account> [branch]"
  echo "Example: $0 blackwd-bwh [main]"
  exit 1
fi

REPO="${ACCOUNT}/features"
echo "📦 Using repository: https://github.com/$REPO (branch: $BRANCH)"

# ===============================================
# Check if branch exists
# ===============================================
if ! git ls-remote --heads "https://github.com/$REPO.git" "$BRANCH" | grep -q "$BRANCH"; then
  echo "❌ Error: Branch '$BRANCH' not found in $REPO"
  exit 1
fi

# ===============================================
# Clone the repo and find features
# ===============================================
WORKDIR=$(mktemp -d)
trap "rm -rf $WORKDIR" EXIT

git clone --depth 1 --branch "$BRANCH" "https://github.com/$REPO.git" "$WORKDIR/repo"

FEATURES_DIR="$WORKDIR/repo/src"
if [[ ! -d "$FEATURES_DIR" ]]; then
  echo "❌ Error: Expected 'src/' directory not found in $REPO"
  exit 1
fi

# ===============================================
# Let user select a feature
# ===============================================
MENU_ITEMS=()
for feature_path in "$FEATURES_DIR"/*; do
  if [[ -f "$feature_path/devcontainer-feature.json" ]]; then
    feature_id=$(basename "$feature_path")
    description=$(jq -r '.description // "No description."' "$feature_path/devcontainer-feature.json")
    MENU_ITEMS+=("$feature_id" "$description")
  fi
done

if [[ ${#MENU_ITEMS[@]} -eq 0 ]]; then
  echo "❌ No valid features found in $REPO/src"
  exit 1
fi

CHOICE=$(dialog \
  --clear \
  --title "Features in $REPO" \
  --menu "Select a feature to configure:" 20 70 15 \
  "${MENU_ITEMS[@]}" \
  3>&1 1>&2 2>&3)

clear
[[ -z "$CHOICE" ]] && echo "No selection made." && exit 1

FEATURE_JSON="$FEATURES_DIR/$CHOICE/devcontainer-feature.json"
VERSION=$(jq -r '.version // "latest"' "$FEATURE_JSON")

# ===============================================
# Collect configuration options
# ===============================================
OPTIONS_BLOCK=$(jq -c '.options' "$FEATURE_JSON")
declare -A SELECTED_OPTIONS

for key in $(echo "$OPTIONS_BLOCK" | jq -r 'keys[]'); do
  type=$(echo "$OPTIONS_BLOCK" | jq -r --arg key "$key" '.[$key].type')
  desc=$(echo "$OPTIONS_BLOCK" | jq -r --arg key "$key" '.[$key].description // "No description."')
  default=$(echo "$OPTIONS_BLOCK" | jq -r --arg key "$key" '.[$key].default')

  if [[ "$type" == "string" && $(echo "$OPTIONS_BLOCK" | jq -r --arg key "$key" '.[$key].proposals | length') -gt 0 ]]; then
    # Show proposals as radio list
    PROPOSALS=($(echo "$OPTIONS_BLOCK" | jq -r --arg key "$key" '.[$key].proposals[]'))
    RADIO_ITEMS=()
    for val in "${PROPOSALS[@]}"; do
      RADIO_ITEMS+=("$val" "$desc" "$([[ "$val" == "$default" ]] && echo "on" || echo "off")")
    done
    SELECTED=$(dialog --radiolist "$desc" 15 60 8 "${RADIO_ITEMS[@]}" 3>&1 1>&2 2>&3 || true)
    SELECTED_OPTIONS[$key]="${SELECTED:-$default}"
  elif [[ "$type" == "string" ]]; then
    SELECTED=$(dialog --inputbox "$desc" 10 60 "$default" 3>&1 1>&2 2>&3 || true)
    SELECTED_OPTIONS[$key]="${SELECTED:-$default}"
  elif [[ "$type" == "boolean" ]]; then
    if dialog --yesno "$desc" 8 60; then
      SELECTED_OPTIONS[$key]="true"
    elif [[ $? -eq 1 ]]; then
      SELECTED_OPTIONS[$key]="false"
    else
      echo "❌ Cancelled."
      exit 1
    fi
  else
    echo "⚠️ Skipping unsupported type: $type for option $key"
  fi
done

# ===============================================
# Print final configuration line
# ===============================================
echo ""
echo "✅ Final configuration:"
echo -n "$CHOICE:$VERSION"
for key in "${!SELECTED_OPTIONS[@]}"; do
  echo -n " $key=${SELECTED_OPTIONS[$key]}"
done
echo
