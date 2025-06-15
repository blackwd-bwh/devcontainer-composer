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
# Check if the branch exists on the remote
# ===============================================
if ! git ls-remote --heads "https://github.com/$REPO.git" "$BRANCH" | grep -q "$BRANCH"; then
  echo "❌ Error: Branch '$BRANCH' not found in $REPO"
  exit 1
fi

# ===============================================
# Clone the repository into a temp directory
# ===============================================
WORKDIR=$(mktemp -d)
trap "rm -rf $WORKDIR" EXIT

git clone --depth 1 --branch "$BRANCH" "https://github.com/$REPO.git" "$WORKDIR/repo"

FEATURES_DIR="$WORKDIR/repo/src"
if [[ ! -d "$FEATURES_DIR" ]]; then
  echo "❌ Error: Expected directory 'src/' not found in $REPO"
  exit 1
fi

# ===============================================
# Build dialog menu from feature metadata
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

# ===============================================
# Show feature menu using dialog
# ===============================================
CHOICE=$(dialog \
  --clear \
  --title "Features in $REPO" \
  --menu "Select a feature to explore:" 20 70 15 \
  "${MENU_ITEMS[@]}" \
  3>&1 1>&2 2>&3)

clear
if [[ -n "$CHOICE" ]]; then
  echo "✅ You selected: $CHOICE"
else
  echo "No selection made."
fi
