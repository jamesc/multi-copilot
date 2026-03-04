# Multi-Copilot

Infrastructure for running multiple parallel GitHub Copilot CLI sessions using git worktrees and devcontainers.

Inspired by [Jesse Vincent's workflow](https://blog.fsck.com/2025/10/05/how-im-using-coding-agents-in-september-2025/).

## Overview

This repository provides a **PowerShell module** (Windows host) that enables:
- **Parallel development**: Work on multiple branches simultaneously, each in its own container
- **Isolated environments**: Each worktree gets its own devcontainer with isolated state
- **Easy setup**: Cmdlets automate worktree creation and container management
- **Project-agnostic**: Scaffold any project with `Initialize-CopilotProject`

## Quick Start

### 1. Install the Module

**Option A: Clone and import**

```powershell
git clone https://github.com/jamesc/multi-copilot.git
Import-Module ./multi-copilot/MultiCopilot
```

**Option B: Copy to your modules path**

```powershell
git clone https://github.com/jamesc/multi-copilot.git
Copy-Item -Recurse multi-copilot/MultiCopilot "$($env:PSModulePath -split ';' | Select-Object -First 1)/MultiCopilot"
Import-Module MultiCopilot
```

### 2. Scaffold Your Project

```powershell
cd C:\Projects\my-app
Initialize-CopilotProject
```

This creates:
- `.devcontainer/` — Container configuration (Dockerfile, devcontainer.json, etc.)
- `scripts/smoke-test.sh` — Devcontainer verification script
- `.gitattributes` — Line ending configuration
- `.worktrees/` entry in `.gitignore`

### 3. Customize the Devcontainer

Edit `.devcontainer/Dockerfile` to add your project's dependencies (languages, tools, etc.).

Edit `.devcontainer/devcontainer.json` to:
- Change the `name` to your project name
- Update VS Code extensions for your tech stack

### 4. Set Environment Variables

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

### 5. Start a Worktree Session

```powershell
New-CopilotWorktree feature-branch
```

This will:
1. Create a git worktree at `.worktrees/feature-branch/`
2. Start a devcontainer for that worktree
3. Configure Copilot CLI
4. Launch Copilot in the container

### 6. Check Status

```powershell
Get-CopilotWorktree
```

### 7. Clean Up

```powershell
# Remove a specific worktree and its container
Remove-CopilotWorktree feature-branch

# Clean up orphaned containers and project volumes (prompts first)
Clear-CopilotWorktree
```

## Cmdlets

| Cmdlet | Description |
|--------|-------------|
| `Initialize-CopilotProject` | Scaffold `.devcontainer/` template into a project |
| `New-CopilotWorktree` | Create a worktree and start a devcontainer |
| `Remove-CopilotWorktree` | Remove a worktree and clean up containers |
| `Get-CopilotWorktree` | Show status of all worktrees and containers |
| `Clear-CopilotWorktree` | Remove orphaned containers and project volumes |

All cmdlets support `Get-Help`:

```powershell
Get-Help New-CopilotWorktree -Full
```

### New-CopilotWorktree

```powershell
# Basic usage
New-CopilotWorktree feature-branch

# Create from a specific base branch
New-CopilotWorktree -Branch issue-123 -BaseBranch main

# Run bash instead of copilot
New-CopilotWorktree feature-branch -Command bash

# Start Amp instead of Copilot
New-CopilotWorktree feature-branch -Amp

# Force rebuild of the devcontainer
New-CopilotWorktree feature-branch -Rebuild
```

### Remove-CopilotWorktree

```powershell
Remove-CopilotWorktree feature-branch
Remove-CopilotWorktree -Branch issue-123 -Force
Remove-CopilotWorktree feature-branch -WhatIf   # preview what would happen
```

### Clear-CopilotWorktree

```powershell
Clear-CopilotWorktree              # Interactive — orphaned containers only
Clear-CopilotWorktree -DryRun      # Preview only
Clear-CopilotWorktree -All         # Remove ALL project containers
Clear-CopilotWorktree -WhatIf      # PowerShell standard preview
```

## How It Works

### Git Worktrees

Git worktrees allow multiple working directories linked to the same repository. Each worktree can be on a different branch, enabling parallel development without stashing or committing.

Worktrees are created in `.worktrees/` inside your repo (gitignored).

**Branch Switching**: You can switch branches inside a worktree with `git checkout`. The cmdlets identify worktrees by directory name (not current branch), so `New-CopilotWorktree` and `Remove-CopilotWorktree` work correctly even after switching branches.

### Devcontainers

Each worktree gets its own Docker container with:
- Isolated filesystem
- Pre-configured Copilot CLI (yolo mode by default)
- Git authentication via `GH_TOKEN`

### Path Translation

The tricky part is that git worktrees on Windows use host paths, but inside containers we need container paths. The cmdlets handle this by:
1. Mounting the main `.git` directory at a known location
2. Rewriting worktree `.git` files to use container paths
3. Restoring host paths when exiting

## Module Structure

```
MultiCopilot/
├── MultiCopilot.psd1              # Module manifest
├── MultiCopilot.psm1              # Module loader
├── Public/                        # Exported cmdlets
│   ├── Initialize-CopilotProject.ps1
│   ├── New-CopilotWorktree.ps1
│   ├── Remove-CopilotWorktree.ps1
│   ├── Get-CopilotWorktree.ps1
│   └── Clear-CopilotWorktree.ps1
├── Private/                       # Internal helpers
│   └── GitHelpers.ps1
└── Templates/                     # Project scaffold files
    ├── .devcontainer/
    │   ├── devcontainer.json
    │   ├── Dockerfile
    │   ├── copilot-config.json
    │   ├── mcp-config.json
    │   └── setup-git-auth.sh
    ├── smoke-test.sh
    └── .gitattributes
```

## Customization

### Adding MCP Servers

After scaffolding, edit `.devcontainer/mcp-config.json` in your project:

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

### Project-Specific Worktree Hook

Create `.devcontainer/worktree-up-hook.sh` to run custom setup each time a worktree container starts.

## Requirements

- Windows with PowerShell 5.1+
- Git with worktree support
- Docker Desktop
- Node.js (for devcontainer CLI)
- GitHub CLI (`gh`) for authentication

## License

Copyright 2026 James Casey  
SPDX-License-Identifier: Apache-2.0
