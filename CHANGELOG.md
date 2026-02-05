# Changelog

All notable changes to multi-copilot will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- **Hook support for worktree-up.ps1** - Calls `.devcontainer/worktree-up-hook.ps1` if it exists, passing `WorktreePath`, `Branch`, and `MainRepo` parameters. Allows projects to implement custom per-worktree setup (e.g., generating unique port configs). ([#4](https://github.com/jamesc/multi-copilot/pull/4))
- **Hook support for worktree-down.ps1** - Calls `.devcontainer/worktree-down-hook.ps1` if it exists for custom cleanup (e.g., removing project-specific Docker volumes).
- **Fast path reconnection** - When a container is already running for a worktree, `worktree-up.ps1` skips worktree/container setup and reconnects directly.

### Changed
- **Devcontainer config synced from main** - `worktree-up.ps1` now syncs `.devcontainer/` from the main repo to the worktree before starting the container. Ensures worktrees created from old commits use the latest devcontainer config.
- **Hooks loaded from worktree** - Project hooks are loaded from the worktree path (not main repo), so reconnects use the version that was synced when the worktree was created or last updated.
- **Default command changed to `copilot --yolo`** - The default exec command is now `copilot --yolo` instead of requiring explicit command specification.

### Fixed
- **Worktree reconnection** - Fixed `worktree-up.ps1` to correctly identify worktrees by directory name instead of current branch. Allows reconnecting when you've switched branches inside the container. ([#3](https://github.com/jamesc/multi-copilot/pull/3))
- **Git path pre-fixing on reconnect** - Fixed fast path reconnection to convert git paths from host format to container format before exec. Previously, reconnects would fail because paths were in host format after the finally block reset them.
- **Orphaned container path handling** - Detect and recreate worktrees when the path is inaccessible from Windows (e.g., orphaned `/workspaces/*` paths in git metadata).
- **File lock retry logic** - Added retry logic for `.git` file access during container shutdown, with clear error messages when files are locked.

### Performance
- **Faster container status lookup** - `worktree-status.ps1` now fetches container labels in a single `docker ps` call instead of calling `docker inspect` per container. Reduces Docker API calls from O(n) to O(1).
