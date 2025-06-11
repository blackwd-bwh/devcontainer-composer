# Dev Container Project Composer

An interactive shell-based tool to generate Dev Container projects from templates with rich customization, dependency resolution, and automatic configuration injection. Perfect for teams standardizing development environments using Dev Containers.

---

## 🚀 Features

### ✅ Interactive Dialog-Based Workflow
- Full-screen terminal dialogs (powered by `dialog`) walk you through template selection, project naming, and feature configuration.
- Easy-to-use UI, even in headless terminals or remote shells.

### 🧱 Template Management
- Auto-discovers templates from a dedicated repository structure.
- Select a template interactively based on metadata and descriptions.

### 🌟 Feature Selection with Dependency Resolution
- Automatically resolves `dependsOn` from each feature’s `devcontainer-feature.json`.
- Notifies you of any **implicitly added** dependencies.

---

### 🔗 How Dependency Resolution Works

When you select features during project creation, the Composer intelligently handles dependencies declared in each feature’s `devcontainer-feature.json`. Here's how it works:

#### 📌 Feature Declaration

Each feature includes a `devcontainer-feature.json` file that may define dependencies:

```json
{
  "id": "aws-cli",
  "description": "AWS CLI Tools",
  "dependsOn": {
    "./features/docker": {}
  }
}
```

This means `aws-cli` depends on `docker`.

#### 🔁 Recursive Resolution

- Composer starts with your selected features.
- It examines each one for a `dependsOn` section.
- All listed dependencies are added.
- The resolver then recursively checks dependencies of those dependencies, and so on.

This ensures that **all transitive dependencies** are automatically included.

#### ✅ User Feedback

- After resolving dependencies, the tool informs you which features were auto-included.
- Only your original selections are marked as "explicit"; all others are marked as "implicit".

#### 🧠 De-duplication and Safety

- The resolver uses hash maps to prevent duplicates.
- Infinite loops and circular dependencies are avoided by tracking which features are already resolved.

---

### 🔄 One-Time Setup Wizard
- Prompts for Git repo, GHCR namespace, and defaults.
- Saves config to `~/.devcontainer-composer.conf`.

---

## ⚙️ Configuration System

The Composer supports a **layered configuration system** to control behavior:

### 1. 📂 Config File (`~/.devcontainer-composer.conf`)

Example:
```bash
DEVCONTAINER_REPO="git@github.com:username/dev-containers.git"
GHCR_NAMESPACE="ghcr.io/username"
PROJECT_PARENT="$HOME/projects"
TEMPLATE_BRANCH="main"
TEMPLATE_SUBDIR="src"
FEATURES_SUBDIR="features"
```

This file is automatically created by the setup wizard.

### 2. 🌿 Environment Variables (override config file)
```bash
export DEVCONTAINER_REPO="..."
export GHCR_NAMESPACE="..."
```

### 3. 🧾 Command Line Options (override everything)
```bash
devcontainer-compose --repo "..." --namespace "..." --parent "..." --branch "..."
```

---

## 🧾 Command Line Usage

Run `devcontainer-compose --help` to see:

```text
Usage: devcontainer-compose [OPTIONS]

Dev Container Composer - Create new projects from dev container templates

OPTIONS:
    -r, --repo URL          Dev container repository URL
    -n, --namespace NAME    GHCR namespace for features
    -p, --parent DIR        Parent directory for projects (default: ~/code)
    -b, --branch BRANCH     Template repository branch (default: main)
    -c, --config FILE       Configuration file (default: ~/.devcontainer-composer.conf)
    -h, --help              Show this help message
    --setup                 Run initial setup wizard
```

---

## 🧪 Quick Start

### First-time setup:
```bash
devcontainer-compose --setup
```

### Create a new project:
```bash
devcontainer-compose
```

---

## 🧩 Repository Layout

```
your-dev-containers/
├── src/
│   ├── python/
│   │   ├── .devcontainer/
│   │   │   ├── devcontainer.json
│   │   │   └── Dockerfile
│   │   ├── metadata.json
│   │   └── README.md
│   └── nodejs/
│       └── .devcontainer/
├── features/
│   ├── docker/
│   │   └── devcontainer-feature.json
│   └── aws-cli/
│       └── devcontainer-feature.json
```

---

## 📌 How It Works

1. **Clone**: A temporary clone of your dev container template repo is created.  
2. **Select Template**: You choose a dev container template via a dialog UI.  
3. **Name & Place**: Enter your project name and desired directory.  
4. **Add Features**: Choose optional devcontainer features with auto-resolved dependencies.  
5. **Create Project**: Final directory is scaffolded, config injected, and Git initialized.

---

## 🧠 Advanced Behavior

- **Auto-detects and injects**:
  - `.devcontainer/devcontainer.json` validation  
  - Terminal profile settings for `zsh`  
  - Dotfile + SSH mount configs  
  - AWS credentials mount points  

- **Dependency recursion**:
  - Handles multiple levels of `dependsOn` and avoids duplication
  - Shows you what was added on your behalf

- **Safe and idempotent**:
  - Skips overwriting existing projects  
  - Cleans temp dirs even on user cancellation

---

## 🧼 Troubleshooting

| Problem                         | Solution                                                                 |
|---------------------------------|--------------------------------------------------------------------------|
| No templates found              | Check your repo URL and `TEMPLATE_SUBDIR` setting                        |
| Invalid `devcontainer.json`     | Run `jq .` on the file in your template to confirm it's valid            |
| Repo clone fails                | Confirm SSH keys and Git access; try `https://` URL for debugging        |
| Dialogs don’t render properly   | Run in a full terminal (not VS Code’s internal terminal) or use SSH+tmux |

