#!/bin/bash
set -euo pipefail

DIALOG_TEMP=$(mktemp)
trap 'rm -f "$DIALOG_TEMP"' EXIT

# Step 1: Choose base family
dialog --title "Select Base Image" --menu "Choose a base image:" 12 50 3 \
  "ubuntu" "Ubuntu-based devcontainer" \
  "debian" "Debian-based devcontainer" \
  "alpine" "Alpine-based devcontainer" 2>"$DIALOG_TEMP"

BASE_FAMILY=$(<"$DIALOG_TEMP")

# Step 2: Latest or custom
dialog --title "Select Version Option" --menu "How do you want to select the version?" 10 50 2 \
  "latest" "Use the latest tag for $BASE_FAMILY" \
  "select" "Select from available tags" 2>"$DIALOG_TEMP"

VERSION_MODE=$(<"$DIALOG_TEMP")

if [[ "$VERSION_MODE" == "latest" ]]; then
  FINAL_TAG="$BASE_FAMILY"
else
  echo "🔍 Fetching available tags from MCR..."
  MCR_TAGS_URL="https://mcr.microsoft.com/v2/devcontainers/base/tags/list"
  TAGS=$(curl -s "$MCR_TAGS_URL" | jq -r '.tags[]' | grep "^$BASE_FAMILY" | sort)

  # Curate well-known LTS mappings (for user-friendly labels)
  declare -A LTS_MAP
  if [[ "$BASE_FAMILY" == "ubuntu" ]]; then
    LTS_MAP=(
      ["ubuntu"]="Latest LTS"
      ["ubuntu-22.04"]="Jammy (22.04)"
      ["jammy"]="Alias: 22.04"
      ["ubuntu-20.04"]="Focal (20.04)"
      ["focal"]="Alias: 20.04"
    )
  elif [[ "$BASE_FAMILY" == "debian" ]]; then
    LTS_MAP=(
      ["debian"]="Latest Stable"
      ["debian-bookworm"]="Bookworm (12)"
      ["bookworm"]="Alias: 12"
      ["debian-bullseye"]="Bullseye (11)"
      ["bullseye"]="Alias: 11"
    )
  elif [[ "$BASE_FAMILY" == "alpine" ]]; then
    LTS_MAP=(
      ["alpine"]="Latest Stable"
      ["alpine-3.19"]="3.19"
      ["alpine-3.18"]="3.18"
    )
  fi

  TAG_MENU=()
  while IFS= read -r tag; do
    label="${LTS_MAP[$tag]:-Tag: $tag}"
    TAG_MENU+=("$tag" "$label")
  done <<< "$TAGS"

  if [[ ${#TAG_MENU[@]} -eq 0 ]]; then
    dialog --msgbox "No tags found for $BASE_FAMILY." 8 40
    exit 1
  fi

  dialog --title "Choose Tag for $BASE_FAMILY" --menu \
    "Select a version tag for your base image:" 20 60 15 "${TAG_MENU[@]}" 2>"$DIALOG_TEMP"

  FINAL_TAG=$(<"$DIALOG_TEMP")
fi

FINAL_IMAGE="mcr.microsoft.com/devcontainers/base:$FINAL_TAG"

dialog --title "Base Image Selected" --msgbox "✅ You selected:\n\n$FINAL_IMAGE" 10 50
echo "Selected base image: $FINAL_IMAGE"
