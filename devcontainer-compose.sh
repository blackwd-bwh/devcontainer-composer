#!/bin/bash
set -euo pipefail

# ===============================================================
# devcontainer-compose.sh
#
# Interactive wizard that scaffolds a project folder containing a
# `.devcontainer/devcontainer.json` file. The user picks a base image
# from the official devcontainers set and can optionally add GitHub
# features.  Feature dependencies are resolved automatically and the
# resulting configuration is written to disk and committed to Git.
# ===============================================================

#Create temporary file
DIALOG_TEMP=$(mktemp)
#Create temporary directory
WORKDIR=$(mktemp -d)

# Remove temporary files and directories that hold dialog results and
# cloned feature repositories. This function is triggered on normal
# exit as well as on interrupts.
cleanup() {
  rm -f "$DIALOG_TEMP"
  rm -rf "$WORKDIR"
}
# Run cleanup when the script exits normally (EXIT), is interrupted (INT), or terminated (TERM)
trap cleanup EXIT INT TERM

# ---Script Dependency Check ---
# Ensure required utilities are installed. If any are missing the user is
# offered an option to install them via the system package manager.
check_dependencies() {
  # declare local array: missing
  local missing=()
  command -v dialog >/dev/null || missing+=("dialog")
  command -v jq >/dev/null || missing+=("jq")
  command -v git >/dev/null || missing+=("git")
  command -v curl >/dev/null || missing+=("curl")
  
  # if the missing array is not empty..
  if [[ ${#missing[@]} -gt 0 ]]; then
    if dialog --yesno "Missing required dependencies:\n${missing[*]}\n\nAttempt to install them now?" 10 60; then
      if command -v apt-get >/dev/null; then
        sudo apt-get update && sudo apt-get install -y "${missing[@]}"
      elif command -v yum >/dev/null; then
        sudo yum install -y "${missing[@]}"
      elif command -v brew >/dev/null; then
        brew install "${missing[@]}"
      else
        dialog --msgbox "Automatic installation not supported on this system." 8 60
        exit 1
      fi
    else
      dialog --msgbox "We can't proceed without these dependencies :(" 6 60
      exit 1
    fi
  fi
}

# --- Base image selection (from select-base-image.sh) ---
# Present a list of base container families (Ubuntu, Debian, etc.)
# and allow the user to pick either the latest tag or a specific
# version from the Microsoft Container Registry.
select_base_image() {
  dialog --title "Select Base Image" --menu "Choose a base image:" 15 60 9 \
    "ubuntu" "Ubuntu-based devcontainer" \
    "debian" "Debian-based devcontainer" \
    "alpine" "Alpine-based devcontainer" \
    "noble" "Universal (Ubuntu 24.04 LTS)" \
    "focal" "Universal (Ubuntu 20.04 LTS)" \
    "linux" "Universal (Minimal)" \
    2>"$DIALOG_TEMP"

  BASE_SELECTION=$(<"$DIALOG_TEMP")

  if [[ "$BASE_SELECTION" =~ ^(noble|linux|focal)$ ]]; then
    IS_UNIVERSAL=1
    UNIVERSAL_VARIANT="$BASE_SELECTION"
    BASE_FAMILY="universal"
  else
    IS_UNIVERSAL=0
    BASE_FAMILY="$BASE_SELECTION"
  fi

  dialog --title "Select Version Option" --menu \
    "How do you want to select the version for $BASE_SELECTION?" 15 60 9 \
    "latest" "Use the latest tag for $BASE_SELECTION" \
    "select" "Select from available tags" \
    2>"$DIALOG_TEMP"

  VERSION_MODE=$(<"$DIALOG_TEMP")

  if [[ "$VERSION_MODE" == "latest" ]]; then
    FINAL_TAG=$([[ $IS_UNIVERSAL -eq 1 ]] && echo "$UNIVERSAL_VARIANT" || echo "$BASE_FAMILY")
  else
    echo "Fetching available tags from MCR..."
    if [[ $IS_UNIVERSAL -eq 1 ]]; then
      MCR_TAGS_URL="https://mcr.microsoft.com/v2/devcontainers/universal/tags/list"
      TAGS=$(curl -s "$MCR_TAGS_URL" | jq -r '.tags[]' | grep "$UNIVERSAL_VARIANT" | sort -V)
    else
      MCR_TAGS_URL="https://mcr.microsoft.com/v2/devcontainers/base/tags/list"
      TAGS=$(curl -s "$MCR_TAGS_URL" | jq -r '.tags[]' | grep "^$BASE_FAMILY" | sort)
    fi

    declare -A LTS_MAP
    if [[ $IS_UNIVERSAL -eq 0 ]]; then
      case "$BASE_FAMILY" in
        ubuntu)
          LTS_MAP=(
            ["ubuntu"]="Latest LTS"
            ["ubuntu-22.04"]="Jammy (22.04)"
            ["jammy"]="Alias: 22.04"
            ["ubuntu-20.04"]="Focal (20.04)"
            ["focal"]="Alias: 20.04"
          )
          ;;
        debian)
          LTS_MAP=(
            ["debian"]="Latest Stable"
            ["debian-bookworm"]="Bookworm (12)"
            ["bookworm"]="Alias: 12"
            ["debian-bullseye"]="Bullseye (11)"
            ["bullseye"]="Alias: 11"
          )
          ;;
        alpine)
          LTS_MAP=(
            ["alpine"]="Latest Stable"
            ["alpine-3.19"]="3.19"
            ["alpine-3.18"]="3.18"
          )
          ;;
      esac
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
      "Select a version tag for your base image:" 20 60 15 \
      "${TAG_MENU[@]}" 2>"$DIALOG_TEMP"
    FINAL_TAG=$(<"$DIALOG_TEMP")
  fi

  FINAL_IMAGE=$(
    if [[ $IS_UNIVERSAL -eq 1 ]]; then
      echo "mcr.microsoft.com/devcontainers/universal:$FINAL_TAG"
    else
      echo "mcr.microsoft.com/devcontainers/base:$FINAL_TAG"
    fi
  )
}

# --- Feature discovery and configuration ---
GITHUB_ACCOUNTS=("devcontainers" "blackwd-bwh")
BRANCH="main"
declare -A FEATURE_PATHS
declare -A FEATURE_ORIGINS
declare -A FEATURE_OPTS
declare -A FEATURE_VERSIONS

clone_repo() {
  local account="$1"
  local repo="https://github.com/$account/features.git"
  local target_dir="$WORKDIR/$account"
  echo "Cloning $repo..." >&2
  if git clone --quiet --depth 1 --branch "$BRANCH" "$repo" "$target_dir"; then
    echo "Cloned $account/features" >&2
    echo "$target_dir/src"
  else
    echo "Failed to clone $repo" >&2
    return 1
  fi
}

# Clone each feature repository listed in GITHUB_ACCOUNTS and build a
# menu of available features for the user to choose from.  The function
# records the path and origin account for every discovered feature.
gather_all_features() {
  ALL_MENU_ITEMS=()
  for account in "${GITHUB_ACCOUNTS[@]}"; do
    src_path=$(clone_repo "$account") || continue
    for feature_path in "$src_path"/*; do
      if [[ -f "$feature_path/devcontainer-feature.json" ]]; then
        feature_id="$(basename "$feature_path")"
        desc=$(jq -r '.description // "No description."' "$feature_path/devcontainer-feature.json")
        key="$account:$feature_id"
        FEATURE_PATHS["$key"]="$feature_path"
        FEATURE_ORIGINS["$key"]="$account"
        ALL_MENU_ITEMS+=("$key" "$(printf '%-20s' "$desc")" "off")
      fi
    done
  done
}

# Display a checklist dialog built from ALL_MENU_ITEMS and capture the
# user's feature selections.  The chosen feature keys are stored in the
# SELECTED_FEATURES array.
select_features() {
  if dialog --checklist "Select features to include:\n(Use SPACE to select)" 30 150 12 \
    "${ALL_MENU_ITEMS[@]}" 2>"$WORKDIR/selected"; then
    read -ra SELECTED_FEATURES <<< "$(tr -d '"' < "$WORKDIR/selected")"
  else
    SELECTED_FEATURES=()
  fi
}

## ---------------------------------------------------------------------------
## Dependency Resolution Helpers
## ---------------------------------------------------------------------------

# Fetch devcontainer-feature.json from GitHub for a ghcr.io feature reference.
# Used when a feature was not cloned locally so we can still resolve its
# dependencies.
fetch_remote_feature_json() {
  local ref="$1"                           # ghcr.io/<owner>/features/<id>:<tag>
  local owner feature
  owner="$(echo "$ref" | cut -d/ -f2)"
  feature="$(echo "$ref" | cut -d/ -f4 | cut -d: -f1)"
  curl -fsSL "https://raw.githubusercontent.com/$owner/features/main/src/$feature/devcontainer-feature.json" 2>/dev/null || true
}

# Recursively resolve `dependsOn` entries for a feature reference. The
# function adds every discovered dependency to the RESOLVED map so that
# it is only processed once.
resolve_dependencies() {
  local ref="$1"                   # fully qualified ghcr feature reference

  # Avoid infinite recursion if already processed
  [[ -n "${RESOLVED[$ref]+_}" ]] && return
  RESOLVED["$ref"]=1

  local owner feature key json deps path
  owner="$(echo "$ref" | cut -d/ -f2)"
  feature="$(echo "$ref" | cut -d/ -f4 | cut -d: -f1)"
  key="$owner:$feature"

  # Prefer local clone if available, else fetch from GitHub
  if [[ -n "${FEATURE_PATHS[$key]+_}" ]]; then
    path="${FEATURE_PATHS[$key]}/devcontainer-feature.json"
    json="$(cat "$path")"
  else
    json="$(fetch_remote_feature_json "$ref")"
  fi

  # Grab dependency keys, if any
  deps=$(echo "$json" | jq -r '.dependsOn | keys[]?' 2>/dev/null || true)
  for dep in $deps; do
    # Strip local relative prefixes
    dep="${dep#./features/}"
    dep="${dep#./}"

    # Expand to ghcr reference if not already
    if [[ "$dep" != ghcr.io/* ]]; then
      dep="ghcr.io/$owner/features/$dep:latest"
    fi
    [[ "$dep" != *:* ]] && dep+=":latest"

    resolve_dependencies "$dep"
  done
}

# Resolve the dependency graph for all user selected features. The
# final set of fully qualified feature references is stored in
# ALL_FEATURE_REFS and any automatically added dependencies are
# presented back to the user.
resolve_all_dependencies() {
  declare -gA RESOLVED=()
  declare -gA USER_MAP=()
  ALL_FEATURE_REFS=()
  IMPLICIT_ADDITIONS=()

  if [[ ${#SELECTED_FEATURES[@]} -eq 0 ]]; then
    return
  fi

  # Map user selections for later comparison
  for key in "${SELECTED_FEATURES[@]}"; do
    USER_MAP["$key"]=1
    origin="${FEATURE_ORIGINS[$key]}"
    id="${key#*:}"
    version="${FEATURE_VERSIONS[$key]}"
    resolve_dependencies "ghcr.io/$origin/features/$id:$version"
  done

  # Build final list of feature refs
  if [[ ${#RESOLVED[@]} -gt 0 ]]; then
    mapfile -t ALL_FEATURE_REFS < <(printf "%s\n" "${!RESOLVED[@]}" | sort)
  else
    ALL_FEATURE_REFS=()
  fi

  # Compute which refs were added implicitly
  IMPLICIT_ADDITIONS=()
  for ref in "${ALL_FEATURE_REFS[@]}"; do
    owner="$(echo "$ref" | cut -d/ -f2)"
    feature="$(echo "$ref" | cut -d/ -f4 | cut -d: -f1)"
    key="$owner:$feature"
    [[ -z "${USER_MAP[$key]+_}" ]] && IMPLICIT_ADDITIONS+=("$ref")
  done

  # Inform the user if we added dependencies automatically
  if [[ ${#IMPLICIT_ADDITIONS[@]} -gt 0 ]]; then
    local msg="The following dependent features were automatically added:\n\n"
    for f in "${IMPLICIT_ADDITIONS[@]}"; do
      msg+="• $f\n"
    done
    dialog --title "Dependencies Added" --msgbox "$msg" 15 60
  fi
}

# Prompt the user for configuration options defined by a feature's
# devcontainer-feature.json. Selected options and versions are stored
# so they can be merged into the final devcontainer.json.
configure_feature() {
  local key="$1"
  local path="${FEATURE_PATHS[$key]}"
  local version
  version=$(jq -r '.version // "latest"' "$path/devcontainer-feature.json")
  local options_json
  options_json=$(jq -c '.options // {}' "$path/devcontainer-feature.json")
  declare -A selected_opts

  if [[ "$options_json" != "{}" ]]; then
    for opt in $(echo "$options_json" | jq -r 'keys[]'); do
      type=$(echo "$options_json" | jq -r --arg opt "$opt" '.[$opt].type')
      desc=$(echo "$options_json" | jq -r --arg opt "$opt" '.[$opt].description // "No description"')
      default=$(echo "$options_json" | jq -r --arg opt "$opt" '.[$opt].default')

      if [[ "$type" == "string" && $(echo "$options_json" | jq -r --arg opt "$opt" '.[$opt].proposals | length') -gt 0 ]]; then
        mapfile -t options < <(echo "$options_json" | jq -r --arg opt "$opt" '.[$opt].proposals[]')
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
          echo "Cancelled."
          exit 1
        fi
      else
        echo "Skipping unsupported option type: $type"
      fi
    done
  fi

  local opts="{}"
  for k in "${!selected_opts[@]}"; do
    if [[ ${selected_opts[$k]} =~ ^(true|false)$ ]]; then
      opts=$(echo "$opts" | jq --arg k "$k" --argjson v "${selected_opts[$k]}" '. + {($k): $v}')
    else
      opts=$(echo "$opts" | jq --arg k "$k" --arg v "${selected_opts[$k]}" '. + {($k): $v}')
    fi
  done
  FEATURE_OPTS["$key"]="$opts"
  FEATURE_VERSIONS["$key"]="$version"
}

# Prompt the user for a destination directory and project name. The
# function will create the directory (removing an existing one if the
# user approves) and store the path in DEST_DIR.
get_project_destination() {
  DEFAULT_PARENT="$HOME/code"

  while true; do
    # Ask for parent directory
    if ! dialog --title "Select Project Location" --inputbox \
      "Enter the parent directory where the new project folder should go:" 10 60 "$DEFAULT_PARENT" 2>"$DIALOG_TEMP"; then
      echo "Cancelled."
      exit 1
    fi
    PARENT_DIR=$(<"$DIALOG_TEMP")
    [[ -z "$PARENT_DIR" ]] && echo "No parent directory provided." && exit 1
    PARENT_DIR="${PARENT_DIR%/}" # remove trailing slash

    # Ask for project name
    if ! dialog --title "Project Name" --inputbox "Enter your new project name:" 8 50 2>"$DIALOG_TEMP"; then
      echo "Cancelled."
      exit 1
    fi
    PROJECT_NAME=$(<"$DIALOG_TEMP")
    [[ -z "$PROJECT_NAME" ]] && echo "No project name provided." && exit 1

    DEST_DIR="$PARENT_DIR/$PROJECT_NAME"

    # Confirm
    if ! dialog --title "Confirm" --yesno "Project directory will be:\n$DEST_DIR\n\nProceed?" 10 60; then
      echo "Cancelled."
      exit 1
    fi

    if [[ -e "$DEST_DIR" ]]; then
      dialog --title "Directory Exists" --menu "The directory $DEST_DIR already exists. What would you like to do?" 12 60 2 \
        change "Choose a different location" \
        overwrite "Delete and use this directory" 2>"$DIALOG_TEMP"
      CHOICE=$(<"$DIALOG_TEMP")
      if [[ "$CHOICE" == "overwrite" ]]; then
        if dialog --yesno "Delete existing directory and continue?" 8 60; then
          rm -rf "$DEST_DIR"
          mkdir -p "$DEST_DIR/.devcontainer"
          break
        else
          continue
        fi
      else
        # choose a different location
        continue
      fi
    else
      mkdir -p "$DEST_DIR/.devcontainer"
      break
    fi
  done
}

# Generate the final .devcontainer/devcontainer.json using the selected
# base image and features. The file is written to DEST_DIR and an
# initial Git repository is created if one does not already exist.
write_devcontainer() {
  mkdir -p "$DEST_DIR/.devcontainer"
  local features_obj="{}"

  for ref in "${ALL_FEATURE_REFS[@]}"; do
    owner="$(echo "$ref" | cut -d/ -f2)"
    feature="$(echo "$ref" | cut -d/ -f4 | cut -d: -f1)"
    key="$owner:$feature"
    if [[ -n "${FEATURE_OPTS[$key]+_}" ]]; then
      opts="${FEATURE_OPTS[$key]}"
    else
      opts="{}"
    fi
    features_obj=$(echo "$features_obj" | jq --arg ref "$ref" --argjson opt "$opts" '. + {($ref): $opt}')
  done

  jq -n \
    --arg image "$FINAL_IMAGE" \
    --argjson features "$features_obj" \
    'if ($features | length) == 0 then {image: $image} else {image: $image, features: $features} end' \
    > "$DEST_DIR/.devcontainer/devcontainer.json"

  echo ".devcontainer/devcontainer.json created at $DEST_DIR/.devcontainer/devcontainer.json"

  if command -v git >/dev/null && [[ ! -d "$DEST_DIR/.git" ]]; then
    (
      cd "$DEST_DIR"
      git init -b main
      git add .
      git commit -m "Initial commit"
    )
  fi
}

# --- Main Execution ---
# Run the helper functions in order to compose the dev container
# definition and scaffold the project.
check_dependencies
select_base_image
gather_all_features
select_features
for feat in "${SELECTED_FEATURES[@]}"; do
  configure_feature "$feat"
done
resolve_all_dependencies
get_project_destination
write_devcontainer
