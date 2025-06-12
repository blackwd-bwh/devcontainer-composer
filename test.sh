# Merge the manifest-based logic into the full script the user provided
# Replaces clone_devcontainer_repo, select_template, and select_features
# Keeps configuration and dialog structure intact

#!/bin/bash
set -euo pipefail

# =============================================================================
# Dev Container Composer (Manifest-Based)
# =============================================================================

DEFAULT_CONFIG_FILE="$HOME/.devcontainer-composer.conf"
DEFAULT_PROJECT_PARENT="$HOME/code"
MANIFEST_FILE="manifest.json"
DIALOG_TEMP=$(mktemp)
trap 'rm -f "$DIALOG_TEMP"' EXIT

load_config() {
    if [[ -f "$DEFAULT_CONFIG_FILE" ]]; then
        source "$DEFAULT_CONFIG_FILE"
    fi

    PROJECT_PARENT="${PROJECT_PARENT:-${DEFAULT_PROJECT_PARENT}}"
}

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Dev Container Composer (Manifest-Based)

OPTIONS:
    -p, --parent DIR        Parent directory for projects (default: $DEFAULT_PROJECT_PARENT)
    -c, --config FILE       Configuration file (default: $DEFAULT_CONFIG_FILE)
    -h, --help              Show this help message
    --setup                 Run initial setup wizard
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--parent)
                PROJECT_PARENT="$2"
                shift 2
                ;;
            -c|--config)
                DEFAULT_CONFIG_FILE="$2"
                shift 2
                ;;
            --setup)
                setup_wizard
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

check_dependencies() {
    local missing=()
    command -v dialog >/dev/null || missing+=("dialog")
    command -v jq >/dev/null || missing+=("jq")
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "❌ Missing required dependencies: ${missing[*]}"
        exit 1
    fi
}

select_template() {
    TEMPLATE_SELECTION=$(jq -r '.templates[] | [.id, .description] | @tsv' "$MANIFEST_FILE" | \
        dialog --title "Choose Template" --menu "Select a base template:" 20 60 10 \
        --file /dev/stdin 2>&1 > "$DIALOG_TEMP" || echo "")
    TEMPLATE_ID=$(<"$DIALOG_TEMP")
    [[ -z "$TEMPLATE_ID" ]] && echo "❌ No template selected." && exit 1

    TEMPLATE_GHCR=$(jq -r --arg id "$TEMPLATE_ID" '.templates[] | select(.id == $id) | .ghcr' "$MANIFEST_FILE")
    TEMPLATE_TAG=$(jq -r --arg id "$TEMPLATE_ID" '.templates[] | select(.id == $id) | .defaultTag' "$MANIFEST_FILE")
}

get_project_details() {
    dialog --title "Project Name" --inputbox "Enter your project name:" 8 50 2>"$DIALOG_TEMP"
    PROJECT_NAME=$(<"$DIALOG_TEMP")
    [[ -z "$PROJECT_NAME" ]] && echo "❌ Project name required." && exit 1

    dialog --title "Project Location" --inputbox "Where should the project be created?" 8 70 "$PROJECT_PARENT" 2>"$DIALOG_TEMP"
    PARENT_DIR=$(<"$DIALOG_TEMP")
    DEST_DIR="$PARENT_DIR/$PROJECT_NAME"
    mkdir -p "$DEST_DIR/.devcontainer"
}

select_features() {
    jq -r '.features[] | [.id, .description] | @tsv' "$MANIFEST_FILE" | \
        dialog --title "Select Features" --checklist "Choose features to include:" 20 70 10 \
        --file /dev/stdin 2>"$DIALOG_TEMP"
    SELECTED=$(<"$DIALOG_TEMP" | tr -d '"')
    read -ra FEATURE_IDS <<< "$SELECTED"

    jq_filter='map(select(.id as $id | $ARGS.positional[] | contains($id)))'
    FEATURE_BLOCK=$(jq -r --argjson ids "$(printf '%s\n' "${FEATURE_IDS[@]}" | jq -R . | jq -s .)" \
        --argjson features "$(jq '.features' "$MANIFEST_FILE")" \
        '($features | map(select(.id as $id | $ids | index($id)))) | map("\(.ghcr):\(.defaultTag)")' \
        <<< '{}' | jq -R 'split("\\n")[:-1] | map({(.): {}}) | add')
}

create_project() {
    cat > "$DEST_DIR/.devcontainer/devcontainer.json" <<EOF
{
  "name": "$PROJECT_NAME",
  "image": "$TEMPLATE_GHCR:$TEMPLATE_TAG",
  "features": $FEATURE_BLOCK,
  "postCreateCommand": "bash .devcontainer/bootstrap.sh",
  "settings": {
    "terminal.integrated.defaultProfile.linux": "zsh",
    "terminal.integrated.shellIntegration.enabled": true,
    "terminal.integrated.profiles.linux": {
      "zsh": {
        "path": "/usr/bin/zsh",
        "args": ["-l"]
      }
    },
    "editor.formatOnSave": true
  },
  "mounts": [
    "source=${env:HOME}/.ssh/dotfiles_deploy_key,target=/root/.ssh/dotfiles_deploy_key,type=bind,consistency=cached",
    "source=${localEnv:HOME}/.ssh,target=/mnt/ssh,type=bind,consistency=cached",
    "source=${localEnv:HOME}/.aws,target=/root/.aws,type=bind,consistency=cached",
    "source=${localEnv:HOME}/.aws/sso/cache,target=/root/.aws/sso/cache,type=bind,consistency=cached",
    "source=${localEnv:HOME}/code/dotfiles,target=/root/code/dotfiles,type=bind,consistency=cached",
    "source=${env:HOME}/.dotfiles_token,target=/root/.dotfiles_token,type=bind,consistency=cached"
  ],
  "remoteUser": "root",
  "updateRemoteUserUID": true,
  "overrideCommand": false,
  "remoteEnv": {
    "HOME": "/root",
    "SHELL": "/usr/bin/zsh"
  }
}
EOF

    cd "$DEST_DIR"
    git init -b main
    git add .
    git commit -m "Initial commit using $TEMPLATE_ID template"
}

main() {
    trap cleanup EXIT
    parse_args "$@"
    load_config
    check_dependencies

    if [[ ! -f "$MANIFEST_FILE" ]]; then
        echo "❌ No manifest.json found in working directory."
        exit 1
    fi

    select_template
    get_project_details
    select_features
    create_project

    dialog --title "Success!" --msgbox "✅ Project created successfully!\n\nLocation: $DEST_DIR" 10 60
}

cleanup() {
    rm -f "$DIALOG_TEMP"
}

main "$@"
