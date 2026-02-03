# Copilot Instructions for Multi-Copilot

This is a template repository for running multiple parallel GitHub Copilot CLI sessions using git worktrees and devcontainers on Windows hosts.

## Project Structure

- `.devcontainer/` - Devcontainer configuration files
- `scripts/` - PowerShell scripts for worktree management

## Key Files

- `scripts/worktree-up.ps1` - Creates worktree and starts devcontainer
- `scripts/worktree-down.ps1` - Removes worktree and cleans up container
- `scripts/worktree-status.ps1` - Shows all worktrees and container status
- `scripts/worktree-cleanup.ps1` - Removes orphaned containers and project volumes
- `scripts/smoke-test.sh` - Verifies devcontainer setup

## Usage

This is a template - users copy these files to their own projects and customize:
1. Edit `Dockerfile` to add project dependencies
2. Edit `devcontainer.json` to add VS Code extensions
3. Edit `mcp-config.json` to add MCP servers

## Common Customizations

### Adding Environment Variables

Pass host environment variables to the container via `remoteEnv` in `devcontainer.json`:

```json
"remoteEnv": {
  "MY_API_KEY": "${localEnv:MY_API_KEY}",
  "DATABASE_URL": "${localEnv:DATABASE_URL}"
}
```

For MCP servers that need tokens, add the env var to both `remoteEnv` and the server's `env` in `mcp-config.json`.

### Adding Cache Volumes

Use named volumes for package caches to speed up rebuilds. In `devcontainer.json`:

```json
"mounts": [
  "source=${localWorkspaceFolderBasename}-npm-cache,target=/home/vscode/.npm,type=volume",
  "source=${localWorkspaceFolderBasename}-pip-cache,target=/home/vscode/.cache/pip,type=volume",
  "source=${localWorkspaceFolderBasename}-go-cache,target=/home/vscode/go,type=volume"
]
```

Common cache paths:
- npm: `/home/vscode/.npm`
- pip: `/home/vscode/.cache/pip`
- Go modules: `/home/vscode/go`
- Cargo: `/home/vscode/.cargo`
- Maven: `/home/vscode/.m2`

### Adding MCP Servers

Edit `.devcontainer/mcp-config.json` to add servers:

```json
{
  "mcpServers": {
    "my-server": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@my-org/my-mcp-server"],
      "env": {
        "API_TOKEN": "${MY_API_TOKEN}"
      }
    }
  }
}
```

### Installing Dependencies in Dockerfile

Add language runtimes and tools to `.devcontainer/Dockerfile`:

```dockerfile
# Python
RUN apt-get update && apt-get install -y python3 python3-pip

# Go
RUN apt-get update && apt-get install -y golang-go

# Project dependencies
COPY requirements.txt /tmp/
RUN pip install -r /tmp/requirements.txt
```

## Running Scripts

From PowerShell on Windows host:
```powershell
.\scripts\worktree-up.ps1 <branch-name>
.\scripts\worktree-down.ps1 <branch-name>
```
