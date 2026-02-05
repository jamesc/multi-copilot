# Scripts

Helper scripts for git worktree + devcontainer workflows.

Worktrees are created in `.worktrees/` subdirectory inside the repo (inspired by [Jesse Vincent's workflow](https://blog.fsck.com/2025/10/05/how-im-using-coding-agents-in-september-2025/)).

## Worktree Scripts

| Script | Description |
|--------|-------------|
| `worktree-up.ps1` | Create a worktree and start a devcontainer |
| `worktree-down.ps1` | Remove a worktree and clean up containers |
| `worktree-status.ps1` | Show status of all worktrees and containers |
| `worktree-cleanup.ps1` | Remove orphaned containers and project volumes |
| `smoke-test.sh` | Verify devcontainer is working (run inside container) |

---

## `worktree-up.ps1`

Start a Copilot devcontainer session for a git worktree branch. This enables running multiple parallel Copilot sessions, each in its own container working on a different branch.

### Usage

```powershell
.\scripts\worktree-up.ps1 feature-branch

# Create new branch from main
.\scripts\worktree-up.ps1 -Branch issue-123 -BaseBranch main
```

### What it does

1. **Checks if worktree exists** for the branch
2. **Creates worktree** if needed (new branch from base, or existing branch)
3. **Starts the devcontainer** using `devcontainer up`
4. **Configures Copilot CLI** with config and MCP servers
5. **Launches Copilot** in the container

You'll get a shell inside the container where you can run Copilot CLI or other tools.

### Switching Branches

You can switch branches inside a worktree (e.g., `git checkout other-branch`). The scripts identify worktrees by their **directory name**, not the current branch, so:

- `worktree-up.ps1 feature-branch` will reconnect to the container even if you've switched branches
- `worktree-down.ps1 feature-branch` will remove the worktree even if you've switched branches

The scripts show an informational message when the current branch differs from the worktree name.

### Prerequisites

- Git with worktree support
- VS Code with Dev Containers extension
- `devcontainer` CLI (auto-installed if missing): `npm install -g @devcontainers/cli`
- `GH_TOKEN` environment variable set

---

## `worktree-down.ps1`

Stop and remove a git worktree, handling container path fixups automatically.

### Usage

```powershell
.\scripts\worktree-down.ps1 feature-branch

# Force remove even with uncommitted changes
.\scripts\worktree-down.ps1 -Branch issue-123 -Force
```

### What it does

1. **Finds the worktree** by directory name (not current branch)
2. **Stops and removes the devcontainer**
3. **Fixes the .git file** if it was modified for container paths
4. **Removes the worktree** using `git worktree remove`
5. **Falls back to manual cleanup** if standard removal fails
6. **Optionally deletes the branch** (prompts you)

The script identifies worktrees by their **directory name** (based on the original branch name), so it works even if you've switched branches inside the worktree.

### Why this is needed

When a worktree is used inside a devcontainer, the `.git` file gets modified to point to container paths (`/workspaces/...`). This breaks `git worktree remove` on the host system. The script fixes the path before removal.

---

## `worktree-cleanup.ps1`

Remove containers and project volumes from worktrees that were deleted without using `worktree-down.ps1`.

```powershell
.\scripts\worktree-cleanup.ps1        # Interactive
.\scripts\worktree-cleanup.ps1 -DryRun # Preview only
.\scripts\worktree-cleanup.ps1 -NoConfirm # Auto-confirm
.\scripts\worktree-cleanup.ps1 -All   # Remove ALL project containers
```

Shows orphaned containers with their worktree names and lets you confirm before removal. Volumes are matched by project name and skipped if in use.

---

## Environment Variables

Set these on your Windows host before using the scripts:

| Variable | Required | Description |
|----------|----------|-------------|
| `GH_TOKEN` | Yes | GitHub auth token (`gh auth token`) |
| `GIT_USER_NAME` | No | Git commit author name |
| `GIT_USER_EMAIL` | No | Git commit author email |
| `GIT_SIGNING_KEY` | No | SSH key name for commit signing |

Example setup:

```powershell
$env:GH_TOKEN = (gh auth token)
$env:GIT_USER_NAME = "Your Name"
$env:GIT_USER_EMAIL = "your.email@example.com"
$env:GIT_SIGNING_KEY = "id_ed25519"
```

---

## Customization

### Adding Project-Specific Environment

Edit `devcontainer.json` to add environment variables via `containerEnv` or `remoteEnv`:

```json
"containerEnv": {
  "MY_VAR": "value"
},
"remoteEnv": {
  "MY_TOKEN": "${localEnv:MY_TOKEN}"
}
```

### Changing the Default Model

Edit `model` in `.devcontainer/copilot-config.json`:

```json
{
  "model": "gpt-4o"
}
```
