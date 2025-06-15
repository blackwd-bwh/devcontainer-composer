#!/bin/bash
set -euo pipefail

# ===============================================
# Multi-source Dev Container Feature Picker
# Supports multiple GitHub accounts (e.g. devcontainers, blackwd-bwh)
# Discovers all features under `src/`, prompts for options, and outputs config
# ===============================================

# Hardcoded GitHub accounts to search from
GITHUB_ACCOUNTS=("devcontainers" "blackwd-bwh")
BRANCH="main"

# Temporary working space
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# Final results
declare -A FEATURE_PATHS
declare -A FEATURE_ORIGINS
declare -A SELECTED_CONFIGS

# -----------------------------------------------
# Clone a GitHub repo if it matches <account>/features
# and return its src/ path
# -----------------------------------------------
clone_repo() {
    local account="$1"
    local repo="https://github.com/$account/features.git"
    local target_dir="$WORKDIR/$account"

    echo "📥 Cloning $repo..." >&2
    if git clone --quiet --depth 1 --branch "$BRANCH" "$repo" "$target_dir"; then
        echo "✅ Cloned $account/features" >&2
        echo "$target_dir/src"
    else
        echo "❌ Failed to clone $repo" >&2
        return 1
    fi
}

# -----------------------------------------------
# Discover all features in all accounts
# -----------------------------------------------
gather_all_features() {
    for account in "${GITHUB_ACCOUNTS[@]}"; do
        src_path=$(clone_repo "$account") || continue
        for feature_path in "$src_path"/*; do
            if [[ -f "$feature_path/devcontainer-feature.json" ]]; then
                feature_id="$(basename "$feature_path")"
                desc=$(jq -r '.description // "No description."' "$feature_path/devcontainer-feature.json")
                key="$account:$feature_id"
                FEATURE_PATHS["$key"]="$feature_path"
                FEATURE_ORIGINS["$key"]="$account"
		ALL_MENU_ITEMS+=("$key" "$(printf '%-20s %s' "$desc")" "off")
            fi
        done
    done
}

# -----------------------------------------------
# Show checklist dialog to select multiple features
# -----------------------------------------------
select_features() {
    dialog --checklist "Select features to include:\n(Use SPACE to select)" 30 150 12 \
        "${ALL_MENU_ITEMS[@]}" 2> "$WORKDIR/selected"
    read -ra SELECTED_FEATURES <<< "$(tr -d '"' < "$WORKDIR/selected")"
}

# -----------------------------------------------
# Prompt for options for each selected feature
# -----------------------------------------------
configure_feature() {
    local key="$1"
    local path="${FEATURE_PATHS[$key]}"
    local id="$(basename "$path")"
    local origin="${FEATURE_ORIGINS[$key]}"
    local version=$(jq -r '.version // "latest"' "$path/devcontainer-feature.json")
    local options_json=$(jq -c '.options' "$path/devcontainer-feature.json")
    local -A selected_opts

    echo "⚙️ Configuring: $key"

    for opt in $(echo "$options_json" | jq -r 'keys[]'); do
        type=$(echo "$options_json" | jq -r --arg opt "$opt" '.[$opt].type')
        desc=$(echo "$options_json" | jq -r --arg opt "$opt" '.[$opt].description // "No description"')
        default=$(echo "$options_json" | jq -r --arg opt "$opt" '.[$opt].default')

        if [[ "$type" == "string" && $(echo "$options_json" | jq -r --arg opt "$opt" '.[$opt].proposals | length') -gt 0 ]]; then
            options=($(echo "$options_json" | jq -r --arg opt "$opt" '.[$opt].proposals[]'))
            radio_items=()
            for val in "${options[@]}"; do
                radio_items+=("$val" "$desc" "$([[ "$val" == "$default" ]] && echo "on" || echo "off")")
            done
            selected=$(dialog --radiolist "$desc" 15 60 8 "${radio_items[@]}" 3>&1 1>&2 2>&3 || true)
            selected_opts["$opt"]="${selected:-$default}"
        elif [[ "$type" == "string" ]]; then
            selected=$(dialog --inputbox "$desc" 10 60 "$default" 3>&1 1>&2 2>&3 || true)
            selected_opts["$opt"]="${selected:-$default}"
        elif [[ "$type" == "boolean" ]]; then
            if dialog --yesno "$desc" 8 60; then
                selected_opts["$opt"]="true"
            elif [[ $? -eq 1 ]]; then
                selected_opts["$opt"]="false"
            else
                echo "❌ Cancelled."
                exit 1
            fi
        else
            echo "⚠️  Skipping unsupported option type: $type"
        fi
    done

    SELECTED_CONFIGS["$key"]="version=$version $(for k in "${!selected_opts[@]}"; do echo -n "$k=${selected_opts[$k]} "; done)"
}

# -----------------------------------------------
# Output result
# -----------------------------------------------
print_results() {
    echo -e "\n✅ Final Configuration:"
    for key in "${!SELECTED_CONFIGS[@]}"; do
        origin="${FEATURE_ORIGINS[$key]}"
        id="${key#*:}"
        version=$(echo "${SELECTED_CONFIGS[$key]}" | grep -o 'version=[^ ]*' | cut -d= -f2)
        options=$(echo "${SELECTED_CONFIGS[$key]}" | sed 's/version=[^ ]*//')
        echo "ghcr.io/$origin/features/$id:$version $options"
    done
}

# ========== MAIN EXECUTION ==========

ALL_MENU_ITEMS=()
gather_all_features
select_features

for feature in "${SELECTED_FEATURES[@]}"; do
    configure_feature "$feature"
done

print_results
