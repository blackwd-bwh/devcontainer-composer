# Dev Container Project Scaffolder

A powerful interactive tool for creating new projects from dev container templates with automatic feature dependency resolution.

## Features

- **Interactive Template Selection** - Browse and select from your dev container templates
- **Feature Management** - Add features with automatic dependency resolution
- **Configurable** - Support for different repositories and namespaces
- **One-time Setup** - Configure once, use everywhere
- **Smart Project Creation** - Automatic git initialization and structure setup

## Installation

1. Download the script:
```bash
curl -o devcontainer-scaffolder https://raw.githubusercontent.com/your-username/devcontainer-scaffolder/main/scaffolder.sh
chmod +x devcontainer-scaffolder
```

2. Move to your PATH:
```bash
sudo mv devcontainer-scaffolder /usr/local/bin/
```

## Dependencies

- `whiptail` (for interactive menus)
- `jq` (for JSON processing)
- `git` (for repository operations)

Install on Ubuntu/Debian:
```bash
sudo apt install whiptail jq git
```

Install on macOS:
```bash
brew install newt jq git
```

## Quick Start

1. **First-time setup:**
```bash
devcontainer-scaffolder --setup
```

2. **Create a new project:**
```bash
devcontainer-scaffolder
```

## Configuration

### Setup Wizard
Run the setup wizard to configure your repository and preferences:
```bash
devcontainer-scaffolder --setup
```

### Manual Configuration
Create `~/.devcontainer-scaffolder.conf`:
```bash
# Dev Container Scaffolder Configuration
DEVCONTAINER_REPO="git@github.com:username/dev-containers.git"
GHCR_NAMESPACE="ghcr.io/username"
PROJECT_PARENT="$HOME/projects"
TEMPLATE_BRANCH="main"
TEMPLATE_SUBDIR="src"
FEATURES_SUBDIR="features"
```

### Environment Variables
You can also use environment variables:
```bash
export DEVCONTAINER_REPO="git@github.com:username/dev-containers.git"
export GHCR_NAMESPACE="ghcr.io/username"
devcontainer-scaffolder
```

## Usage

### Basic Usage
```bash
devcontainer-scaffolder
```

### Command Line Options
```bash
devcontainer-scaffolder [OPTIONS]

OPTIONS:
    -r, --repo URL          Dev container repository URL
    -n, --namespace NAME    GHCR namespace for features
    -p, --parent DIR        Parent directory for projects
    -b, --branch BRANCH     Template repository branch
    -c, --config FILE       Configuration file
    -h, --help              Show help message
    --setup                 Run setup wizard
```

### Examples

**Use a different repository:**
```bash
devcontainer-scaffolder --repo "https://github.com/other-user/templates.git"
```

**Override project parent directory:**
```bash
devcontainer-scaffolder --parent "/path/to/projects"
```

**Use a specific branch:**
```bash
devcontainer-scaffolder --branch "development"
```

## Repository Structure

Your dev container repository should follow this structure:

```
your-dev-containers/
├── src/                    # Templates directory
│   ├── python/
│   │   ├── .devcontainer/
│   │   │   ├── devcontainer.json
│   │   │   └── Dockerfile
│   │   ├── metadata.json
│   │   └── README.md
│   └── nodejs/
│       ├── .devcontainer/
│       └── metadata.json
└── features/               # Features directory (optional)
    ├── docker/
    │   └── devcontainer-feature.json
    └── aws-cli/
        └── devcontainer-feature.json
```

### Template Metadata
Each template should have a `metadata.json` file:
```json
{
  "id": "python",
  "name": "Python Development",
  "description": "Python development environment with common tools"
}
```

### Feature Dependencies
Features can declare dependencies in `devcontainer-feature.json`:
```json
{
  "id": "my-feature",
  "description": "My awesome feature",
  "dependsOn": {
    "./features/docker": {}
  }
}
```

## How It Works

1. **Template Selection** - Browse available templates from your repository
2. **Project Details** - Specify project name and location
3. **Feature Selection** - Choose features with automatic dependency resolution
4. **Project Creation** - Copy template files, inject features, initialize git
5. **Ready to Go** - Open in VS Code with dev containers

## Customization

### Adding Custom Configuration
The scaffolder supports injecting custom configuration into `devcontainer.json`. You can modify the script to add your own default settings, mounts, or environment variables.

### Supporting Different Repository Layouts
If your repository uses a different structure, you can adjust the `TEMPLATE_SUBDIR` and `FEATURES_SUBDIR` configuration variables.

## Troubleshooting

### Common Issues

**"No templates found"**
- Check that your repository URL is correct
- Verify the `TEMPLATE_SUBDIR` matches your repository structure
- Ensure templates have the correct directory structure

**"Failed to clone repository"**
- Verify your SSH keys are set up correctly
- Check that the repository URL is accessible
- Try using HTTPS instead of SSH

**"Invalid devcontainer.json"**
- Ensure your template's `devcontainer.json` is valid JSON
- Check for syntax errors in the template files

### Debug Mode
For debugging, you can modify the script to add `set -x` at the top to see detailed execution.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with different repository structures
5. Submit a pull request

## License

MIT License - see LICENSE file for details.

## Acknowledgments

- Inspired by the VS Code Dev Containers extension
- Built for the dev container community
