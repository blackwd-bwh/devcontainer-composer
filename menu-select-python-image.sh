#!/bin/bash
set -euo pipefail

# Temporary files
TMP_VARIANTS=$(mktemp)
TMP_MENU=$(mktemp)

# Step 1: Fetch variants.json from GitHub
echo "Fetching available Python image tags from GitHub..."
VARIANTS_JSON_URL=$(curl -s https://api.github.com/repos/devcontainers/images/contents/src/python/variants.json \
  | jq -r '.download_url')

curl -s "$VARIANTS_JSON_URL" -o "$TMP_VARIANTS"

# Step 2: Extract variant IDs
variant_list=()
while IFS= read -r id; do
  variant_list+=("$id" "" )  # Empty description to work with dialog
done < <(jq -r '.variants[].id' "$TMP_VARIANTS")

# Step 3: Show dialog menu
dialog --clear --title "Select Python Base Image" \
  --menu "Choose a Python version for your DevContainer:" 15 50 6 \
  "${variant_list[@]}" 2> "$TMP_MENU"

# Capture the selection
if [[ $? -ne 0 ]]; then
  echo "Cancelled."
  exit 1
fi

selection=$(<"$TMP_MENU")
selected_image="mcr.microsoft.com/vscode/devcontainers/python:$selection"
echo "You selected: $selected_image"

# Step 4: Write devcontainer.json
mkdir -p .devcontainer
cat > .devcontainer/devcontainer.json <<EOF
{
  "name": "Python DevContainer ($selection)",
  "image": "$selected_image",
  "features": {},
  "postCreateCommand": "echo 'DevContainer ready with Python $selection'"
}
EOF

echo "✅ .devcontainer/devcontainer.json created with image: $selected_image"

# Cleanup
rm -f "$TMP_VARIANTS" "$TMP_MENU"
