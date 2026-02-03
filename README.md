# Multi-Copilot

Infrastructure for running multiple parallel GitHub Copilot CLI sessions using git worktrees and devcontainers.

Inspired by [Jesse Vincent's workflow](https://blog.fsck.com/2025/10/05/how-im-using-coding-agents-in-september-2025/).

## Overview

This repository provides reusable infrastructure (Windows host + PowerShell) that enables:
- **Parallel development**: Work on multiple branches simultaneously, each in its own container
- **Isolated environments**: Each worktree gets its own devcontainer with isolated state
- **Easy setup**: PowerShell scripts automate worktree creation and container management
- **Project-agnostic**: Copy these files to any project to enable multi-copilot workflows

## Quick Start

### 1. Copy to Your Project

Copy the following to your project:
- `.devcontainer/` - Devcontainer configuration
- `scripts/` - Worktree management scripts
- `.gitattributes` - Ensures shell scripts have correct line endings

### 2. Customize the Devcontainer

Edit `.devcontainer/Dockerfile` to add your project's dependencies (languages, tools, etc.).

Edit `.devcontainer/devcontainer.json` to:
- Change the `name` to your project name
- Update VS Code extensions for your tech stack

### 3. Set Environment Variables

Set these on your Windows host:

```powershell
# Required: GitHub authentication
$env:GH_TOKEN = (gh auth token)

# Optional: Git identity
$env:GIT_USER_NAME = "Your Name"
$env:GIT_USER_EMAIL = "your.email@example.com"

# Optional: SSH commit signing
$env:GIT_SIGNING_KEY = "id_ed25519"  # or your key name
```

### 4. Start a Worktree Session

**Option A: PowerShell scripts (for parallel Copilot CLI sessions)**

```powershell
.\scripts\worktree-up.ps1 feature-branch
```

**Option B: VS Code (for single-session development)**

Open the folder in VS Code with the Dev Containers extension installed. VS Code will prompt to reopen in container.

This will:
1. Create a git worktree at `.worktrees/feature-branch/`
2. Start a devcontainer for that worktree
3. Configure Copilot CLI
4. Launch Copilot in the container

### 5. Verify Setup

Inside the container, run:

```bash
bash scripts/smoke-test.sh
```

### 6. Check Status

```powershell
.\scripts\worktree-status.ps1
```

### 7. Clean Up

```powershell
# Remove a specific worktree and its container
.\scripts\worktree-down.ps1 feature-branch

# Clean up orphaned containers and project volumes (prompts first)
.\scripts\worktree-cleanup.ps1
```

## How It Works

### Git Worktrees

Git worktrees allow multiple working directories linked to the same repository. Each worktree can be on a different branch, enabling parallel development without stashing or committing.

Worktrees are created in `.worktrees/` inside your repo (gitignored).

### Devcontainers

Each worktree gets its own Docker container with:
- Isolated filesystem
- Pre-configured Copilot CLI (yolo mode by default)
- Git authentication via `GH_TOKEN`

### Path Translation

The tricky part is that git worktrees on Windows use host paths, but inside containers we need container paths. The scripts handle this by:
1. Mounting the main `.git` directory at a known location
2. Rewriting worktree `.git` files to use container paths
3. Restoring host paths when exiting

## File Structure

```
.devcontainer/
├── devcontainer.json      # Container configuration
├── Dockerfile             # Build dependencies (customize this)
├── copilot-config.json    # Copilot CLI settings (yolo mode)
├── mcp-config.json        # MCP server configuration
└── setup-git-auth.sh      # Configure git authentication

scripts/
├── worktree-up.ps1        # Create worktree + start container
├── worktree-down.ps1      # Remove worktree + stop container
├── worktree-status.ps1    # Show all worktrees and container status
├── worktree-cleanup.ps1   # Clean up orphaned containers
├── smoke-test.sh          # Verify devcontainer setup
└── README.md              # Script documentation
```

## Customization

### Adding MCP Servers

Edit `.devcontainer/mcp-config.json`:

```json
{
  "mcpServers": {
    "your-server": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "your-mcp-server"],
      "env": {
        "API_TOKEN": "${YOUR_API_TOKEN}"
      }
    }
  }
}
```

Then add the env var to `remoteEnv` in `devcontainer.json`.

### Adding Environment Variables

Add to `remoteEnv` in `devcontainer.json`:

```json
"remoteEnv": {
  "MY_TOKEN": "${localEnv:MY_TOKEN}"
}
```

## Requirements

- Windows with PowerShell 5.1+ (scripts are PowerShell/Windows-focused)
- Git with worktree support
- Docker Desktop
- Node.js (for devcontainer CLI)
- GitHub CLI (`gh`) for authentication

## License

Copyright 2026 James Casey  
SPDX-License-Identifier: Apache-2.0
