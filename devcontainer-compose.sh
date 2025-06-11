#!/bin/bash
set -euo pipefail

# =============================================================================
# Dev Container Composer (Dialog Version)
# =============================================================================

# Default configuration - can be overridden by config file or environment variables
DEFAULT_CONFIG_FILE="$HOME/.devcontainer-composer.conf"
DEFAULT_DEVCONTAINER_REPO=""
DEFAULT_GHCR_NAMESPACE=""
DEFAULT_PROJECT_PARENT="$HOME/code"
DEFAULT_TEMPLATE_BRANCH="main"
DEFAULT_TEMPLATE_SUBDIR="src"
DEFAULT_FEATURES_SUBDIR="features"

# Dialog temporary file for responses
DIALOG_TEMP=$(mktemp)
trap 'rm -f "$DIALOG_TEMP"' EXIT

# Load configuration
load_config() {
    # Load from config file if it exists
    if [[ -f "$DEFAULT_CONFIG_FILE" ]]; then
        source "$DEFAULT_CONFIG_FILE"
    fi

    # Environment variables override config file
    DEVCONTAINER_REPO="${DEVCONTAINER_REPO:-${DEFAULT_DEVCONTAINER_REPO}}"
    GHCR_NAMESPACE="${GHCR_NAMESPACE:-${DEFAULT_GHCR_NAMESPACE}}"
    PROJECT_PARENT="${PROJECT_PARENT:-${DEFAULT_PROJECT_PARENT}}"
    TEMPLATE_BRANCH="${TEMPLATE_BRANCH:-${DEFAULT_TEMPLATE_BRANCH}}"
    TEMPLATE_SUBDIR="${TEMPLATE_SUBDIR:-${DEFAULT_TEMPLATE_SUBDIR}}"
    FEATURES_SUBDIR="${FEATURES_SUBDIR:-${DEFAULT_FEATURES_SUBDIR}}"
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Dev Container Composer - Create new projects from dev container templates

OPTIONS:
    -r, --repo URL          Dev container repository URL
    -n, --namespace NAME    GHCR namespace for features
    -p, --parent DIR        Parent directory for projects (default: $DEFAULT_PROJECT_PARENT)
    -b, --branch BRANCH     Template repository branch (default: $DEFAULT_TEMPLATE_BRANCH)
    -c, --config FILE       Configuration file (default: $DEFAULT_CONFIG_FILE)
    -h, --help              Show this help message
    --setup                 Run initial setup wizard

CONFIGURATION:
    Configuration can be set via:
    1. Configuration file: $DEFAULT_CONFIG_FILE
    2. Environment variables
    3. Command line options (highest priority)

    Example config file:
        DEVCONTAINER_REPO="git@github.com:user/dev-containers.git"
        GHCR_NAMESPACE="ghcr.io/user"
        PROJECT_PARENT="$HOME/projects"
        TEMPLATE_BRANCH="main"
        TEMPLATE_SUBDIR="templates"
        FEATURES_SUBDIR="features"

EOF
}

# Setup wizard for first-time users
setup_wizard() {
    dialog --title "Dev Container Composer Setup" --msgbox "Welcome to Dev Container Composer Setup\n\nThis wizard will help you configure the tool for first-time use." 10 60

    # Get repository URL
    if ! dialog --title "Repository Setup" --inputbox "Enter your dev container repository URL (SSH or HTTPS):" 10 70 2>"$DIALOG_TEMP"; then
        echo "Setup cancelled."
        exit 1
    fi
    REPO_URL=$(cat "$DIALOG_TEMP")
    [[ -z "$REPO_URL" ]] && echo "Setup cancelled - no repository URL provided." && exit 1

    # Get GHCR namespace
    if ! dialog --title "Feature Registry" --inputbox "Enter your GHCR namespace for features:\n(e.g., ghcr.io/username)" 10 70 2>"$DIALOG_TEMP"; then
        echo "Setup cancelled."
        exit 1
    fi
    NAMESPACE=$(cat "$DIALOG_TEMP")
    [[ -z "$NAMESPACE" ]] && echo "Setup cancelled - no namespace provided." && exit 1

    # Get default project parent
    if ! dialog --title "Project Location" --inputbox "Enter default parent directory for projects:" 10 70 "$DEFAULT_PROJECT_PARENT" 2>"$DIALOG_TEMP"; then
        echo "Setup cancelled."
        exit 1
    fi
    PARENT=$(cat "$DIALOG_TEMP")
    [[ -z "$PARENT" ]] && echo "Setup cancelled - no parent directory provided." && exit 1

    # Optional: Advanced settings
    if dialog --title "Advanced Settings" --yesno "Would you like to configure advanced settings?\n(branch, subdirectories)\n\nSelect 'No' to use defaults." 10 60; then

        dialog --title "Repository Branch" --inputbox "Template repository branch:" 8 50 "$DEFAULT_TEMPLATE_BRANCH" 2>"$DIALOG_TEMP" || true
        BRANCH=$(cat "$DIALOG_TEMP")
        BRANCH="${BRANCH:-$DEFAULT_TEMPLATE_BRANCH}"

        dialog --title "Templates Directory" --inputbox "Subdirectory containing templates:" 8 50 "$DEFAULT_TEMPLATE_SUBDIR" 2>"$DIALOG_TEMP" || true
        TEMPLATE_DIR=$(cat "$DIALOG_TEMP")
        TEMPLATE_DIR="${TEMPLATE_DIR:-$DEFAULT_TEMPLATE_SUBDIR}"

        dialog --title "Features Directory" --inputbox "Subdirectory containing features:" 8 50 "$DEFAULT_FEATURES_SUBDIR" 2>"$DIALOG_TEMP" || true
        FEATURES_DIR=$(cat "$DIALOG_TEMP")
        FEATURES_DIR="${FEATURES_DIR:-$DEFAULT_FEATURES_SUBDIR}"
    else
        BRANCH="$DEFAULT_TEMPLATE_BRANCH"
        TEMPLATE_DIR="$DEFAULT_TEMPLATE_SUBDIR"
        FEATURES_DIR="$DEFAULT_FEATURES_SUBDIR"
    fi

    # Write configuration
    cat > "$DEFAULT_CONFIG_FILE" << EOF
# Dev Container Composer Configuration
DEVCONTAINER_REPO="$REPO_URL"
GHCR_NAMESPACE="$NAMESPACE"
PROJECT_PARENT="$PARENT"
TEMPLATE_BRANCH="$BRANCH"
TEMPLATE_SUBDIR="$TEMPLATE_DIR"
FEATURES_SUBDIR="$FEATURES_DIR"
EOF

    dialog --title "Setup Complete" --msgbox "✅ Configuration saved to $DEFAULT_CONFIG_FILE\n\nYou can now run the composer without --setup" 8 60
    exit 0
}

# Check dependencies
check_dependencies() {
    local missing=()

    command -v dialog >/dev/null || missing+=("dialog")
    command -v jq >/dev/null || missing+=("jq")
    command -v git >/dev/null || missing+=("git")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "❌ Missing required dependencies: ${missing[*]}"
        echo "Please install them and try again."
        echo
        echo "On Ubuntu/Debian: sudo apt install dialog jq git"
        echo "On macOS: brew install dialog jq git"
        echo "On RHEL/CentOS: sudo yum install dialog jq git"
        exit 1
    fi
}

# Validate configuration
validate_config() {
    if [[ -z "$DEVCONTAINER_REPO" ]]; then
        echo "❌ No dev container repository configured."
        echo "Run: $(basename "$0") --setup"
        exit 1
    fi

    if [[ -z "$GHCR_NAMESPACE" ]]; then
        echo "❌ No GHCR namespace configured."
        echo "Run: $(basename "$0") --setup"
        exit 1
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--repo)
                DEVCONTAINER_REPO="$2"
                shift 2
                ;;
            -n|--namespace)
                GHCR_NAMESPACE="$2"
                shift 2
                ;;
            -p|--parent)
                PROJECT_PARENT="$2"
                shift 2
                ;;
            -b|--branch)
                TEMPLATE_BRANCH="$2"
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

# Clone dev container repository
clone_devcontainer_repo() {
    DEVCONTAINER_LOCAL="$(mktemp -d)"
    TEMPLATE_ROOT="$DEVCONTAINER_LOCAL/$TEMPLATE_SUBDIR"
    FEATURES_ROOT="$DEVCONTAINER_LOCAL/$FEATURES_SUBDIR"

    echo "🔄 Cloning dev-container repo into temp directory..."
    if ! git clone --depth 1 --branch "$TEMPLATE_BRANCH" "$DEVCONTAINER_REPO" "$DEVCONTAINER_LOCAL"; then
        echo "❌ Failed to clone repository. Check your repository URL and credentials."
        exit 1
    fi

    if [[ ! -d "$TEMPLATE_ROOT" ]]; then
        echo "❌ Templates directory '$TEMPLATE_SUBDIR' not found in repository"
        exit 1
    fi
}

# Select template
select_template() {
    TEMPLATE_DIRS=$(find "$TEMPLATE_ROOT" -maxdepth 1 -mindepth 1 -type d | xargs -n1 basename)
    
    if [[ -z "$TEMPLATE_DIRS" ]]; then
        dialog --title "Error" --msgbox "❌ No templates found in $TEMPLATE_ROOT" 8 60
        exit 1
    fi

    # Build menu options for dialog
    local menu_items=()
    for dir in $TEMPLATE_DIRS; do
        META_FILE="$TEMPLATE_ROOT/$dir/metadata.json"
        if [[ -f "$META_FILE" ]]; then
            DESC=$(jq -r '.description // "No description"' "$META_FILE" 2>/dev/null || echo "No description")
        else
            DESC="Template: $dir"
        fi
        menu_items+=("$dir" "$DESC")
    done

    if ! dialog --title "Choose Dev Container Template" \
        --menu "Select a base template:" 20 78 10 "${menu_items[@]}" 2>"$DIALOG_TEMP"; then
        echo "Template selection cancelled."
        exit 1
    fi
    
    TEMPLATE_NAME=$(cat "$DIALOG_TEMP")
    if [[ -z "$TEMPLATE_NAME" ]]; then
        echo "❌ No template selected"
        exit 1
    fi
}

# Get project details
get_project_details() {
    # Project parent directory
    if ! dialog --title "Select Project Location" --inputbox \
        "Enter the parent directory where the new project should go:" 10 60 "$PROJECT_PARENT" 2>"$DIALOG_TEMP"; then
        echo "Project setup cancelled."
        exit 1
    fi
    PARENT_DIR=$(cat "$DIALOG_TEMP")
    [[ -z "$PARENT_DIR" ]] && echo "Cancelled - no parent directory provided." && exit 1
    PARENT_DIR="${PARENT_DIR%/}"

    # Project name
    if ! dialog --title "Project Name" --inputbox "Enter your new project name:" 8 50 2>"$DIALOG_TEMP"; then
        echo "Project setup cancelled."
        exit 1
    fi
    PROJECT_NAME=$(cat "$DIALOG_TEMP")
    [[ -z "$PROJECT_NAME" ]] && echo "Cancelled - no project name provided." && exit 1

    DEST_DIR="$PARENT_DIR/$PROJECT_NAME"

    # Confirm details
    if ! dialog --title "Confirm Project Details" --yesno \
"Project Name: $PROJECT_NAME
Template: $TEMPLATE_NAME
Destination: $DEST_DIR

Continue with project creation?" 12 60; then
        echo "Project creation cancelled by user."
        exit 1
    fi

    # Validate destination
    if [[ -d "$DEST_DIR" ]]; then
        dialog --title "Error" --msgbox "❌ Project directory already exists:\n$DEST_DIR\n\nPlease choose a different name or location." 10 60
        exit 1
    fi
}

# Select features (only if features directory exists)
select_features() {
    ALL_FEATURES=()

    if [[ ! -d "$FEATURES_ROOT" ]]; then
        echo "ℹ️  No features directory found, skipping feature selection"
        return
    fi

    FEATURE_DIRS=$(find "$FEATURES_ROOT" -mindepth 1 -maxdepth 1 -type d | xargs -n1 basename 2>/dev/null || true)

    if [[ -z "$FEATURE_DIRS" ]]; then
        echo "ℹ️  No features found, skipping feature selection"
        return
    fi

    # Build checklist options for dialog
    local checklist_items=()
    for feat in $FEATURE_DIRS; do
        DESC=$(jq -r '.description // .id // "Feature"' "$FEATURES_ROOT/$feat/devcontainer-feature.json" 2>/dev/null || echo "Feature: $feat")
        checklist_items+=("$feat" "$DESC" "off")
    done

    if ! dialog --title "Choose Features" --checklist \
        "Select which features to include:\n(Use SPACE to select, ENTER to confirm)" 20 70 10 "${checklist_items[@]}" 2>"$DIALOG_TEMP"; then
        echo "Feature selection cancelled."
        exit 1
    fi

    # Process feature selection and dependencies
    FEATURE_CHOICES_RAW=$(cat "$DIALOG_TEMP")
    read -ra USER_SELECTED <<< "$(echo "$FEATURE_CHOICES_RAW" | tr -d '"')"
    
    if [[ ${#USER_SELECTED[@]} -eq 0 ]]; then
        echo "ℹ️  No features selected"
        return
    fi

    declare -A RESOLVED=()
    declare -A USER_MAP=()
    for f in "${USER_SELECTED[@]}"; do
        RESOLVED["$f"]=1
        USER_MAP["$f"]=1
    done

    # Recursive dependency resolver
    resolve_dependencies() {
        local base="$1"
        local feature="$2"
        local path="$base/$feature/devcontainer-feature.json"

        if [[ ! -f "$path" ]]; then return; fi

        local deps
        deps=$(jq -r '.dependsOn | keys[]?' "$path" 2>/dev/null || true)
        for dep in $deps; do
            local dep_name="${dep#./features/}"
            if [[ -z "${RESOLVED[$dep_name]+_}" ]]; then
                RESOLVED["$dep_name"]=1
                resolve_dependencies "$base" "$dep_name"
            fi
        done
    }

    for feat in "${USER_SELECTED[@]}"; do
        resolve_dependencies "$FEATURES_ROOT" "$feat"
    done

    ALL_FEATURES=($(for f in "${!RESOLVED[@]}"; do
      if [[ "$f" == ghcr.io/* ]]; then
        echo "$f"
      else
        echo "$GHCR_NAMESPACE/$f:latest"
      fi
    done | sort))

    IMPLICIT_ADDITIONS=()
    for f in "${ALL_FEATURES[@]}"; do
        if [[ -z "${USER_MAP[$f]+_}" ]]; then
            IMPLICIT_ADDITIONS+=("$f")
        fi
    done

    # Notify user of automatic additions
    if [[ ${#IMPLICIT_ADDITIONS[@]} -gt 0 ]]; then
        local msg="The following dependent features were automatically added:\n\n"
        for f in "${IMPLICIT_ADDITIONS[@]}"; do
            msg+="• $f\n"
        done
        dialog --title "Dependencies Added" --msgbox "$msg" 15 60
    fi
}

# Create project
create_project() {
    TEMPLATE_PATH="$TEMPLATE_ROOT/$TEMPLATE_NAME"

    # Create project structure
    mkdir -p "$DEST_DIR/.devcontainer"
    cp -r "$TEMPLATE_PATH/.devcontainer/." "$DEST_DIR/.devcontainer/"
    cp "$TEMPLATE_PATH/metadata.json" "$DEST_DIR/.devcontainer/" 2>/dev/null || true
    cp "$TEMPLATE_PATH/README.md" "$DEST_DIR/" 2>/dev/null || true
    mkdir -p "$DEST_DIR/src"

    # Process devcontainer.json
    DEVCONTAINER_JSON="$DEST_DIR/.devcontainer/devcontainer.json"
    if ! jq empty "$DEVCONTAINER_JSON" 2>/dev/null; then
        echo "❌ ERROR: Invalid devcontainer.json in template. Aborting."
        exit 1
    fi

    # Add features if any were selected
    if [[ ${#ALL_FEATURES[@]} -gt 0 && -n "$GHCR_NAMESPACE" ]]; then
        FEATURES_JSON=$(printf "%s\n" "${ALL_FEATURES[@]}" \
            | sed "s|^|$GHCR_NAMESPACE/|" \
            | jq -Rs 'split("\n")[:-1] | map({ (.): {} }) | add')
        jq --argjson features "$FEATURES_JSON" '.features = $features' \
            "$DEVCONTAINER_JSON" > "$DEVCONTAINER_JSON.tmp" && mv "$DEVCONTAINER_JSON.tmp" "$DEVCONTAINER_JSON"
    fi

   # Inject base configuration
   jq '. + {
     "remoteUser": "root",
     "updateRemoteUserUID": true,
     "overrideCommand": false,
     "remoteEnv": {
       "HOME": "/root",
       "SHELL": "/usr/bin/zsh"
     },
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
     ]
   }' "$DEVCONTAINER_JSON" > "$DEVCONTAINER_JSON.tmp" && mv "$DEVCONTAINER_JSON.tmp" "$DEVCONTAINER_JSON"

    # Initialize git repository
    cd "$DEST_DIR"
    git init -b main
    git add .
    git commit -m "Initial commit using $TEMPLATE_NAME template"
}

# Cleanup function
cleanup() {
    if [[ -n "${DEVCONTAINER_LOCAL:-}" && -d "$DEVCONTAINER_LOCAL" ]]; then
        rm -rf "$DEVCONTAINER_LOCAL"
    fi
    rm -f "$DIALOG_TEMP"
}

# Main function
main() {
    # Setup cleanup trap
    trap cleanup EXIT

    # Parse arguments first
    parse_args "$@"

    # Load configuration
    load_config

    # Check dependencies
    check_dependencies

    # Validate configuration
    validate_config

    # Main workflow
    clone_devcontainer_repo
    select_template
    get_project_details
    select_features
    create_project

    # Success message with dialog
    dialog --title "Success!" --msgbox "✅ Project created successfully!\n\nLocation: $DEST_DIR\n\nYou can now open this directory in VS Code with the Dev Containers extension." 10 60

    echo "Project Summary"
    echo "Name: $PROJECT_NAME"
    echo "Template: $TEMPLATE_NAME"
    echo "Features:"
    printf "  - %s\n" "${ALL_FEATURES[@]}"
    echo "Destination: $DEST_DIR"

}

# Run main function with all arguments
main "$@"
