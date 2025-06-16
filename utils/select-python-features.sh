#!/bin/bash
set -euo pipefail

DIALOG_TEMP=$(mktemp)
trap 'rm -f "$DIALOG_TEMP"' EXIT

# Step 1: Ask if user wants to include the Python feature
if dialog --title "Feature Selection" --checklist \
    "Select features to include:" 10 60 4 \
    "python" "Installs Python via deadsnakes PPA" "on" 2>"$DIALOG_TEMP"; then
    SELECTED=$(cat "$DIALOG_TEMP")
else
    echo "Cancelled"
    exit 1
fi

# Step 2: If selected, show version options with a radiolist
if [[ "$SELECTED" == *"python"* ]]; then
    dialog --title "Select Python Version" --radiolist \
        "Choose a Python version:" 15 50 6 \
        "3.8" "Python 3.8.x" off \
        "3.9" "Python 3.9.x" off \
        "3.10" "Python 3.10.x" off \
        "3.11" "Python 3.11.x" on \
        "3.12" "Python 3.12.x" off \
        "3.13" "Python 3.13.x (preview)" off \
        2>"$DIALOG_TEMP"

    PYTHON_VERSION=$(cat "$DIALOG_TEMP")

    echo
    echo "Generated feature config:"
    jq -n --arg feature "ghcr.io/blackwd-bwh/python" --arg version "$PYTHON_VERSION" '{
      ($feature): { "version": $version }
    }'
else
    echo "No features selected."
fi
