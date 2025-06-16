#!/bin/bash
set -euo pipefail

DIALOG_TEMP=$(mktemp)
trap 'rm -f "$DIALOG_TEMP"' EXIT

# Step 1: Choose base family
dialog --title "Select Base Image" --menu "Choose a base image:" 15 60 9 \
  "ubuntu" "Ubuntu-based devcontainer" \
  "debian" "Debian-based devcontainer" \
  "alpine" "Alpine-based devcontainer" \
  "noble" "Universal (noble)" \
  "linux" "Universal (linux)" \
  "focal" "Universal (focal)" 2>"$DIALOG_TEMP"

BASE_SELECTION=$(<"$DIALOG_TEMP")
if [[ "$BASE_SELECTION" =~ ^(noble|linux|focal)$ ]]; then
  IS_UNIVERSAL=1
  UNIVERSAL_VARIANT="$BASE_SELECTION"
  BASE_FAMILY="universal"
else
  IS_UNIVERSAL=0
  BASE_FAMILY="$BASE_SELECTION"
fi

# Step 2: Latest or custom
dialog --title "Select Version Option" --menu "How do you want to select the version?" 10 50 2 \
  "latest" "Use the latest tag for $BASE_SELECTION" \
  "select" "Select from available tags" 2>"$DIALOG_TEMP"

VERSION_MODE=$(<"$DIALOG_TEMP")

if [[ "$VERSION_MODE" == "latest" ]]; then
  if [[ $IS_UNIVERSAL -eq 1 ]]; then
    FINAL_TAG="$UNIVERSAL_VARIANT"
  else
    FINAL_TAG="$BASE_FAMILY"
  fi
else
  echo "🔍 Fetching available tags from MCR..."
  if [[ $IS_UNIVERSAL -eq 1 ]]; then
    MCR_TAGS_URL="https://mcr.microsoft.com/v2/devcontainers/universal/tags/list"
    TAGS=$(curl -s "$MCR_TAGS_URL" | jq -r '.tags[]' | grep -E "(^$UNIVERSAL_VARIANT$|-$UNIVERSAL_VARIANT$)" | sort -V)
  else
    MCR_TAGS_URL="https://mcr.microsoft.com/v2/devcontainers/base/tags/list"
    TAGS=$(curl -s "$MCR_TAGS_URL" | jq -r '.tags[]' | grep "^$BASE_FAMILY" | sort)
  fi

  # Curate well-known LTS mappings (for user-friendly labels)
  declare -A LTS_MAP
  if [[ $IS_UNIVERSAL -eq 1 ]]; then
    LTS_MAP=()
  elif [[ "$BASE_FAMILY" == "ubuntu" ]]; then
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
    dialog --msgbox "No tags found for $BASE_SELECTION." 8 40
    exit 1
  fi

  dialog --title "Choose Tag for $BASE_SELECTION" --menu \
    "Select a version tag for your base image:" 20 60 15 "${TAG_MENU[@]}" 2>"$DIALOG_TEMP"

  FINAL_TAG=$(<"$DIALOG_TEMP")
fi

if [[ $IS_UNIVERSAL -eq 1 ]]; then
  FINAL_IMAGE="mcr.microsoft.com/devcontainers/universal:$FINAL_TAG"
else
  FINAL_IMAGE="mcr.microsoft.com/devcontainers/base:$FINAL_TAG"
fi

dialog --title "Base Image Selected" --msgbox "✅ You selected:\n\n$FINAL_IMAGE" 10 50
echo "Selected base image: $FINAL_IMAGE"
