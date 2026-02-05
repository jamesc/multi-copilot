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

1. **Checks if container is running** - if yes, reconnects immediately
2. **Checks if worktree exists** for the branch
3. **Creates worktree** if needed (new branch from base, or existing branch)
4. **Starts the devcontainer** using `devcontainer up`
5. **Configures Copilot CLI** with config and MCP servers
6. **Launches Copilot** in the container

You'll get a shell inside the container where you can run Copilot CLI or other tools.

### Reconnecting to an Existing Container

The script supports a "generic workspace" workflow where you:

1. Create a worktree: `worktree-up.ps1 design-sessions`
2. Work inside, create branches for fixes, push them
3. Disconnect from the container
4. Reconnect later: `worktree-up.ps1 design-sessions`

The **worktree name is the container identity**, not the branch. If you switch branches inside the container (e.g., from `design-sessions` to `fix-typo`), reconnecting will preserve your current branch - it won't try to switch back.

```
🚀 Starting worktree session: design-sessions
✅ Container already running for worktree: design-sessions
   Note: Currently on branch 'fix-typo' (worktree was created as 'design-sessions')
🔌 Reconnecting to existing container...
```

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

1. **Finds the worktree** for the given branch
2. **Stops and removes the devcontainer**
3. **Fixes the .git file** if it was modified for container paths
4. **Removes the worktree** using `git worktree remove`
5. **Falls back to manual cleanup** if standard removal fails
6. **Optionally deletes the branch** (prompts you)

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
