# `devcontainer-compose.sh` Script Overview

`devcontainer-compose.sh` is the main interactive script for creating new Dev Container–based projects. Its workflow is split into functions and runs in the `main` function at the bottom of the file. The README also summarizes the high-level steps. The following description walks through the script in order.

---

## 1. Initial Setup

```bash
#!/bin/bash
set -euo pipefail
```

- Exits on any error, unset variable, or failed pipeline.
- Defines default configuration variables:
  - `DEFAULT_CONFIG_FILE`
  - `DEFAULT_DEVCONTAINER_REPO`
  - `DEFAULT_GHCR_NAMESPACE`
  - `DEFAULT_PROJECT_PARENT`
  - `DEFAULT_TEMPLATE_BRANCH`
  - `DEFAULT_TEMPLATE_SUBDIR`
  - `DEFAULT_FEATURES_SUBDIR`

```bash
DIALOG_TEMP=$(mktemp)
trap 'rm -f "$DIALOG_TEMP"' EXIT
```

- Creates a temporary file for dialog responses with cleanup on exit.

---

## 2. Loading Configuration

```bash
load_config
```

- Reads `$HOME/.devcontainer-composer.conf` if present.
- Allows environment variables to override config file values.
- **Lines 21–34**

---

## 3. Showing Help

```bash
show_usage
```

- Prints usage instructions:
  - `--repo`, `--namespace`, `--parent`, `--branch`, `--config`, `--setup`, `--help`
- Exits on unknown options.
- **Lines 38–67**

---

## 4. Setup Wizard

```bash
setup_wizard
```

- Guides first-time users through dialog-based configuration:
  - Collects the repo URL, GHCR namespace, project path
  - Allows advanced setup: template branch and subdirs
  - Writes values to config file
- **Lines 70–130**

---

## 5. Dependency Checks

```bash
check_dependencies
```

- Ensures `dialog`, `jq`, and `git` are installed.
- Shows install instructions if any are missing.
- **Lines 133–150**

---

## 6. Configuration Validation

```bash
validate_config
```

- Confirms repo and namespace are configured.
- Prompts to run setup wizard if missing.
- **Lines 152–165**

---

## 7. Parsing Command-Line Arguments

```bash
parse_args "$@"
```

- Handles command-line flags:
  - `--repo`, `--namespace`, `--parent`, `--branch`, `--config`, `--setup`, `--help`
- Shows usage and exits on unknown args.
- **Lines 167–205**

---

## 8. Cloning the Dev Container Repo

```bash
clone_devcontainer_repo
```

- Clones configured repo into a temporary directory.
- Checks for correct branch and presence of template directory.
- Exits with error on failure.
- **Lines 207–223**

---

## 9. Template Selection

```bash
select_template
```

- Scans template root for subdirectories.
- Reads each `metadata.json` to get the template name and description.
- Uses dialog menu for selection.
- Stores selection as `TEMPLATE_NAME`.
- **Lines 225–257**

---

## 10. Gathering Project Details

```bash
get_project_details
```

- Prompts for:
  - Parent directory (default from config)
  - Project name
  - Final confirmation
- Validates that target directory does not already exist.
- **Lines 259–297**

---

## 11. Feature Selection and Dependency Resolution

```bash
select_features
```

- Lists all features using dialog if features directory exists.
- User selects features.
- `resolve_dependencies` walks each feature’s `devcontainer-feature.json` for `dependsOn`.
- Deduplicates and auto-adds dependencies.
- Shows user a summary if additional features are added.
- **Lines 300–389**

---

## 12. Project Creation

```bash
create_project
```

- Copies selected template to destination directory.
- Validates `devcontainer.json` using `jq`.
- Injects selected features into `features` block.
- Adds base config (remote user, terminal, mounts).
- Initializes Git, stages files, and creates initial commit.
- **Lines 392–461**

---

## 13. Cleanup

```bash
cleanup
```

- Removes temporary clone directory and dialog file.
- Ensures resources are cleaned up on script exit.
- **Lines 463–469**

---

## 14. Main Workflow

```bash
main "$@"
```

- Runs:
  - `parse_args`
  - `load_config`
  - `check_dependencies`
  - `validate_config`
  - `clone_devcontainer_repo`
  - `select_template`
  - `get_project_details`
  - `select_features`
  - `create_project`
- Traps exit for cleanup and shows final success message.
- **Lines 471–505 + main call at line 508**

---

## 15. High-Level Overview from README

The README summarizes the workflow:

1. Clone the dev container template repo.
2. Select a template via dialog.
3. Provide project name and directory.
4. Choose features (with dependencies auto-resolved).
5. Create the project and initialize Git.

- **Lines 160–164 of README.md**

---

## Conclusion

`devcontainer-compose.sh` is a full-screen interactive Bash tool that scaffolds new project directories from Dev Container templates. It handles:

- Config loading
- Dependency checking
- Repo cloning
- Template selection
- Feature selection with dependency resolution
- Project creation
- Cleanup

This structure provides a solid foundation for adding enhancements like manifest-driven builds while preserving the current workflow.
