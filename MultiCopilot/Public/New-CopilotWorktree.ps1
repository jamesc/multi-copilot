# Copyright 2026 James Casey
# SPDX-License-Identifier: Apache-2.0

function New-CopilotWorktree {
    <#
    .SYNOPSIS
        Start a Copilot devcontainer session for a git worktree branch.

    .DESCRIPTION
        Creates a worktree for the given branch (if needed) and starts
        a devcontainer. Each worktree gets its own container for parallel
        Copilot sessions.

    .PARAMETER Branch
        The branch name to work on (e.g., "feature-branch" or "main")

    .PARAMETER BaseBranch
        The base branch to create new branches from (default: auto-detect main/master)

    .PARAMETER WorktreeRoot
        Directory where worktrees are created (default: .worktrees/ inside main repo)

    .PARAMETER Command
        Command to run in container (default: "copilot --yolo")

    .PARAMETER Amp
        Start Amp instead of Copilot (sets Command to "amp")

    .PARAMETER Rebuild
        Force rebuild of the devcontainer image (no cache)

    .EXAMPLE
        New-CopilotWorktree feature-branch

    .EXAMPLE
        New-CopilotWorktree -Branch issue-123 -BaseBranch main

    .EXAMPLE
        New-CopilotWorktree feature-branch -Command bash

    .EXAMPLE
        New-CopilotWorktree feature-branch -Amp

    .EXAMPLE
        New-CopilotWorktree feature-branch -Rebuild
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Branch,

        [Parameter()]
        [string]$BaseBranch = "",

        [Parameter()]
        [string]$WorktreeRoot = "",

        [Parameter()]
        [string]$Command = "copilot --yolo",

        [Parameter()]
        [switch]$Amp,

        [Parameter()]
        [switch]$Rebuild
    )

    $ErrorActionPreference = "Stop"
    $skipWorktreeSetup = $false

    if ($Amp -and $PSBoundParameters.ContainsKey('Command')) {
        Write-Error "-Amp and -Command are mutually exclusive. Use one or the other."
        return
    }

    if ($Amp) {
        $Command = "amp"
    }

    # Check AMP_API_KEY early if using Amp
    if ($Amp -and -not $env:AMP_API_KEY) {
        Write-Host "❌ AMP_API_KEY not set. Required for Amp." -ForegroundColor Red
        Write-Host "   Sign in at: ampcode.com/install" -ForegroundColor Gray
        Write-Host "   Then set: `$env:AMP_API_KEY = <your-key>" -ForegroundColor Gray
        return
    }

    # Main script
    Write-Host "🚀 Starting worktree session: $Branch" -ForegroundColor Cyan

    # Find main repo
    $mainRepo = Get-MainRepoRoot
    $projectName = Get-ProjectName -RepoPath $mainRepo
    Write-Host "📁 Main repo: $mainRepo" -ForegroundColor Gray
    Write-Host "📁 Project: $projectName" -ForegroundColor Gray

    # Set worktree root if not specified (default: .worktrees/ inside repo)
    if (-not $WorktreeRoot) {
        $WorktreeRoot = Join-Path $mainRepo ".worktrees"
    }

    # Sanitize name for directory (replace / with -)
    $dirName = $Branch -replace '/', '-'
    $worktreePath = Join-Path $WorktreeRoot $dirName

    # FAST PATH: If container is already running for this worktree, just reconnect
    # This handles the case where you've switched branches inside the container
    if (Test-Path $worktreePath) {
        if (Test-ContainerRunning -WorktreePath $worktreePath) {
            if ($Rebuild) {
                Write-Host "⚠️  Container already running — cannot rebuild while running." -ForegroundColor Yellow
                Write-Host "   Run: Remove-CopilotWorktree $Branch" -ForegroundColor Gray
                Write-Host "   Then re-run with -Rebuild" -ForegroundColor Gray
                return
            }

            Write-Host "✅ Container already running for worktree: $dirName" -ForegroundColor Green

            # Show what branch is actually checked out (informational only)
            Push-Location $worktreePath
            try {
                $actualBranch = git branch --show-current 2>$null
                if ($actualBranch -and $actualBranch -ne $Branch) {
                    Write-Host "   Note: Currently on branch '$actualBranch' (worktree was created as '$Branch')" -ForegroundColor Gray
                }
            }
            finally {
                Pop-Location
            }

            # Skip to container connection (jump past worktree setup)
            $skipWorktreeSetup = $true
        }
    }

    if (-not $skipWorktreeSetup) {
        # Ensure worktree root exists
        if (-not (Test-Path $WorktreeRoot)) {
            Write-Host "📁 Creating .worktrees directory..." -ForegroundColor Cyan
            New-Item -ItemType Directory -Path $WorktreeRoot -Force | Out-Null
        }

        # Set base branch if not specified
        if (-not $BaseBranch) {
            Push-Location $mainRepo
            try {
                $BaseBranch = Get-DefaultBranch
            }
            finally {
                Pop-Location
            }
            Write-Host "📌 Using default branch: $BaseBranch" -ForegroundColor Gray
        }

        # Check if we're already on this branch in current directory
        $currentBranch = git branch --show-current 2>$null
        $currentDir = Get-Location

        # Always fetch latest from origin first
        Write-Host "🔄 Fetching latest from origin..." -ForegroundColor Cyan
        Push-Location $mainRepo
        try {
            git fetch origin --prune 2>$null
        }
        finally {
            Pop-Location
        }

        if ($currentBranch -eq $Branch) {
            Write-Host "✅ Already on branch $Branch in current directory" -ForegroundColor Green
            $worktreePath = $currentDir.Path
        }
        else {
            # Check if worktree already exists
            Push-Location $mainRepo
            try {
                $existingWorktree = Find-WorktreeForBranch -BranchName $Branch -WorktreeRoot $WorktreeRoot

                if ($existingWorktree -and (Test-Path $existingWorktree)) {
                    # Worktree exists and is accessible from Windows
                    Write-Host "✅ Worktree already exists at: $existingWorktree" -ForegroundColor Green
                    $worktreePath = $existingWorktree
                }
                elseif ($existingWorktree) {
                    # Worktree metadata exists but path is inaccessible (likely orphaned container path)
                    Write-Host "⚠️  Worktree metadata exists but path inaccessible: $existingWorktree" -ForegroundColor Yellow
                    Write-Host "🔄 Removing orphaned worktree and recreating..." -ForegroundColor Cyan
                    git worktree remove $Branch --force 2>$null

                    # Create new worktree at proper Windows path
                    $dirName = $Branch -replace '/', '-'
                    $worktreePath = Join-Path $WorktreeRoot $dirName

                    # Remove directory if it exists (may be leftover from previous container)
                    if (Test-Path $worktreePath) {
                        Write-Host "🗑️  Removing existing directory: $worktreePath" -ForegroundColor Gray
                        try {
                            Remove-Item -Path $worktreePath -Recurse -Force -ErrorAction Stop
                        }
                        catch {
                            Write-Host "❌ Cannot remove directory (may be in use by container)" -ForegroundColor Red
                            Write-Host "   Run: Remove-CopilotWorktree $Branch" -ForegroundColor Gray
                            Write-Host "   Or:  docker stop <container-id>" -ForegroundColor Gray
                            return
                        }
                    }

                    Write-Host "📌 Recreating worktree for branch: $Branch" -ForegroundColor Yellow
                    git worktree add $worktreePath $Branch

                    if ($LASTEXITCODE -ne 0) {
                        Write-Host "❌ Failed to recreate worktree" -ForegroundColor Red
                        return
                    }

                    Write-Host "✅ Worktree recreated at: $worktreePath" -ForegroundColor Green
                }
                else {
                    # Create new worktree
                    # Sanitize branch name for directory (replace / with -)
                    $dirName = $Branch -replace '/', '-'
                    $worktreePath = Join-Path $WorktreeRoot $dirName

                    if (Test-BranchExists -BranchName $Branch) {
                        Write-Host "📌 Creating worktree for existing branch: $Branch" -ForegroundColor Yellow
                        git worktree add $worktreePath $Branch
                    }
                    else {
                        Write-Host "🌱 Creating worktree with new branch: $Branch (from $BaseBranch)" -ForegroundColor Yellow
                        git worktree add -b $Branch $worktreePath $BaseBranch
                    }

                    if ($LASTEXITCODE -ne 0) {
                        Write-Host "❌ Failed to create worktree" -ForegroundColor Red
                        return
                    }

                    Write-Host "✅ Worktree created at: $worktreePath" -ForegroundColor Green
                }
            }
            finally {
                Pop-Location
            }
        }
    } # End of: if (-not $skipWorktreeSetup) for worktree creation

    # Update worktree with latest changes from remote (skip if container already running)
    if (-not $skipWorktreeSetup) {
        if (Test-Path $worktreePath) {
            Write-Host "🔄 Updating worktree with latest changes..." -ForegroundColor Cyan
            Push-Location $worktreePath
            try {
                $trackingBranch = git rev-parse --abbrev-ref "@{upstream}" 2>$null
                if ($trackingBranch) {
                    git pull --ff-only 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "✅ Worktree updated" -ForegroundColor Green
                    }
                    else {
                        Write-Host "⚠️  Could not fast-forward, may need manual merge" -ForegroundColor Yellow
                    }
                }
                else {
                    Write-Host "ℹ️  No upstream tracking branch, skipping pull" -ForegroundColor Gray
                }
            }
            finally {
                Pop-Location
            }
        }
        else {
            Write-Host "ℹ️  Worktree path not accessible from host, will update in container" -ForegroundColor Gray
        }
    } # End of: if (-not $skipWorktreeSetup)

    # Check for devcontainer CLI
    $devcontainerCli = Get-Command devcontainer -ErrorAction SilentlyContinue
    if (-not $devcontainerCli) {
        Write-Host "⚠️  devcontainer CLI not found. Installing..." -ForegroundColor Yellow
        npm install -g @devcontainers/cli
    }

    # Check GH_TOKEN is set (required for GitHub authentication in container)
    if (-not $env:GH_TOKEN) {
        Write-Host "❌ GH_TOKEN not set. Required for GitHub authentication." -ForegroundColor Red
        Write-Host "   Authenticate with: gh auth login" -ForegroundColor Gray
        Write-Host "   Then set: `$env:GH_TOKEN = (gh auth token)" -ForegroundColor Gray
        return
    }

    # Set MAIN_GIT_PATH (auto-derived from main repo)
    $env:MAIN_GIT_PATH = Join-Path $mainRepo ".git"

    # These variables are needed for both setup and reconnect paths
    $worktreeName = Split-Path $worktreePath -Leaf
    $worktreeGitFile = Join-Path $worktreePath ".git"
    $worktreeMetaGitdir = Join-Path $env:MAIN_GIT_PATH "worktrees" $worktreeName "gitdir"

    # Skip container setup if already running - just reconnect
    if ($skipWorktreeSetup) {
        Write-Host "`n🔌 Reconnecting to existing container..." -ForegroundColor Cyan

        # IMPORTANT: Pre-fix git paths for container before exec
        # The finally block resets paths to host format after each run,
        # so we must convert them back to container format before reconnecting
        Write-Host "🔧 Pre-fixing .git paths for container..." -ForegroundColor Cyan
        $containerGitPath = "/workspaces/.$projectName-git/worktrees/$worktreeName"
        Set-Content -Path $worktreeGitFile -Value "gitdir: $containerGitPath" -NoNewline
        Write-Host "   Set .git to: $containerGitPath" -ForegroundColor Gray

        if (Test-Path $worktreeMetaGitdir) {
            Set-Content -Path $worktreeMetaGitdir -Value "/workspaces/$worktreeName" -NoNewline
            Write-Host "   Set gitdir to: /workspaces/$worktreeName" -ForegroundColor Gray
        }
        Write-Host "✅ Git paths pre-configured for container" -ForegroundColor Green

        Invoke-WorktreeUpHook -WorktreePath $worktreePath
    }
    else {
        # Sync devcontainer config from main repo (worktrees may be created from old commits)
        Write-Host "📋 Syncing devcontainer config..." -ForegroundColor Cyan
        $mainDevcontainer = Join-Path $mainRepo ".devcontainer"
        $worktreeDevcontainer = Join-Path $worktreePath ".devcontainer"
        if (Test-Path $mainDevcontainer) {
            Copy-Item -Path "$mainDevcontainer\*" -Destination $worktreeDevcontainer -Force -Recurse
            Write-Host "✅ Synced .devcontainer from main repo" -ForegroundColor Green
        }

        # Pre-fix worktree .git file for container paths BEFORE starting container
        # This prevents "fatal: not a git repository" errors during postStartCommand
        Write-Host "🔧 Pre-fixing .git paths for container..." -ForegroundColor Cyan
        # IMPORTANT: Point to the worktree-specific git directory
        # The .git file contains "gitdir: <directory>" where <directory> is inside .git/worktrees/<name>
        $containerGitPath = "/workspaces/.$projectName-git/worktrees/$worktreeName"
        Set-Content -Path $worktreeGitFile -Value "gitdir: $containerGitPath" -NoNewline
        Write-Host "   Set .git to: $containerGitPath" -ForegroundColor Gray

        # Also fix the gitdir file in the main repo's worktree metadata
        if (Test-Path $worktreeMetaGitdir) {
            Set-Content -Path $worktreeMetaGitdir -Value "/workspaces/$worktreeName" -NoNewline
            Write-Host "   Set gitdir to: /workspaces/$worktreeName" -ForegroundColor Gray
        }
        Write-Host "✅ Git paths pre-configured for container" -ForegroundColor Green

        # Start devcontainer
        Write-Host "`n🐳 Starting devcontainer..." -ForegroundColor Cyan
        Write-Host "   Workspace: $worktreePath" -ForegroundColor Gray

        # Suppress Docker CLI hints (e.g., "Try Docker Debug...")
        $env:DOCKER_CLI_HINTS = "false"

        # Build and start the container - capture output to get container ID
        # Explicitly mount the main .git directory since ${localEnv:...} doesn't work reliably
        $mountArg = "--mount=type=bind,source=$($env:MAIN_GIT_PATH),target=/workspaces/.$projectName-git"
        $rebuildArgs = if ($Rebuild) { "--remove-existing-container" } else { "" }
        $displayCmd = "devcontainer up --workspace-folder $worktreePath $mountArg $rebuildArgs".Trim()
        Write-Host "Running: $displayCmd" -ForegroundColor Gray

        $upArgs = @("up", "--workspace-folder", $worktreePath, $mountArg)
        if ($Rebuild) {
            $upArgs += "--remove-existing-container"
            Write-Host "🔨 Rebuilding devcontainer (removing existing container)..." -ForegroundColor Yellow
        }

        $output = & devcontainer @upArgs 2>&1 | ForEach-Object {
            # Filter out PowerShell's stderr wrapper noise and Docker hints
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $line = $_.Exception.Message
            } else {
                $line = $_
            }
            # Strip devcontainer CLI timestamp prefix (e.g., "[2026-02-06T13:41:03.568Z] ")
            # so downstream regex filters can match the actual content
            $stripped = $line -replace '^\[[\d\-T:.Z]+\]\s*', ''
            # Suppress Docker build noise (layer steps, apt output, download progress, etc.)
            # Keep devcontainer lifecycle output (postCreateCommand, postStartCommand, etc.)
            if ($stripped -and
                $stripped -notmatch '^System\.Management\.Automation\.RemoteException' -and
                $stripped -notmatch "What's next:|Try Docker Debug|Learn more at https://docs\.docker\.com" -and
                $stripped -notmatch '^\s*#\d+\s' -and          # Docker BuildKit step lines (#1, #2 [internal], etc.)
                $stripped -notmatch '^\s*--->' -and              # Legacy Docker builder layer IDs
                $stripped -notmatch '^(Step \d+/\d+|Removing intermediate|Successfully (built|tagged))' -and
                $stripped -notmatch '^(Sending build context|COPY|RUN|FROM|ENV|WORKDIR|ARG|LABEL|EXPOSE|CMD|ENTRYPOINT|ADD|VOLUME|USER|SHELL|ONBUILD|STOPSIGNAL|HEALTHCHECK)' -and
                $stripped -notmatch '^\s*(Get:|Hit:|Ign:|Fetched |Reading |Building )' -and   # apt-get output
                $stripped -notmatch '^\s*(\d+\.\d+ [kMG]B|Downloading|Unpacking|Setting up|Selecting|Preparing|Processing)' -and
                $stripped -notmatch '^\s*(sha256:|digest:|resolve |resolved |DONE |CACHED )' -and
                $stripped -notmatch '^\[[\d/ ]+\]') {            # Docker progress like [1/5]
                Write-Host $stripped
            }
            $line  # Pass through original (with timestamp) to capture for JSON parsing
        }

        if ($LASTEXITCODE -ne 0) {
            Write-Host "`n❌ Failed to start devcontainer" -ForegroundColor Red
            return
        }

        # Extract container ID from output JSON (last line)
        $containerIdFromOutput = $null
        try {
            $lastLine = ($output | Select-Object -Last 1) -replace '\x1b\[[0-9;]*m', ''  # Strip ANSI codes
            $jsonOutput = $lastLine | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($jsonOutput.containerId) {
                $containerIdFromOutput = $jsonOutput.containerId
            }
        } catch {
            # Ignore JSON parse errors
        }

        Write-Host "`n✨ Container ready!" -ForegroundColor Green

        # Set up Copilot CLI config
        Write-Host "🤖 Setting up Copilot CLI config..." -ForegroundColor Cyan
        devcontainer exec --workspace-folder $worktreePath bash -c "mkdir -p ~/.copilot && envsubst < .devcontainer/mcp-config.json > ~/.copilot/mcp-config.json && envsubst < .devcontainer/copilot-config.json > ~/.copilot/config.json" 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Copilot CLI configured" -ForegroundColor Green
        }
        else {
            Write-Host "⚠️  Could not configure Copilot CLI" -ForegroundColor Yellow
        }

        # Set up Amp CLI config
        Write-Host "⚡ Setting up Amp CLI config..." -ForegroundColor Cyan
        devcontainer exec --workspace-folder $worktreePath bash -c "mkdir -p ~/.config/amp && envsubst < .devcontainer/amp-settings.json > ~/.config/amp/settings.json" 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Amp CLI configured" -ForegroundColor Green
        }
        else {
            Write-Host "⚠️  Could not configure Amp CLI" -ForegroundColor Yellow
        }

        Invoke-WorktreeUpHook -WorktreePath $worktreePath

        # Copy SSH signing key if configured
        if ($env:GIT_SIGNING_KEY) {
            # For signing, we need the private key (not .pub)
            # If user specified id_rsa.pub, use id_rsa instead
            $keyName = $env:GIT_SIGNING_KEY -replace '\.pub$', ''
            $privateKeyPath = Join-Path $env:USERPROFILE ".ssh\$keyName"
            $publicKeyPath = Join-Path $env:USERPROFILE ".ssh\$keyName.pub"

            if ((Test-Path $privateKeyPath) -and (Test-Path $publicKeyPath)) {
                Write-Host "🔑 Copying SSH signing keys..." -ForegroundColor Cyan

                # Use container ID from devcontainer up output
                $containerInfo = $containerIdFromOutput

                if ($containerInfo) {
                    Write-Host "   Container ID: $containerInfo" -ForegroundColor Gray

                    # Ensure .ssh directory exists in container with correct ownership
                    docker exec $containerInfo mkdir -p /home/vscode/.ssh 2>$null
                    docker exec $containerInfo chown -R vscode:vscode /home/vscode/.ssh 2>$null
                    docker exec $containerInfo chmod 700 /home/vscode/.ssh 2>$null

                    # Copy private key
                    Write-Host "   Copying private key: $privateKeyPath" -ForegroundColor Gray
                    $privateKeyContent = Get-Content $privateKeyPath -Raw
                    $privateKeyContent | docker exec -i $containerInfo tee /home/vscode/.ssh/$keyName 2>&1 | Out-Null

                    if ($LASTEXITCODE -eq 0) {
                        # Set correct permissions for private key (600)
                        docker exec $containerInfo chown vscode:vscode /home/vscode/.ssh/$keyName 2>$null
                        docker exec $containerInfo chmod 600 /home/vscode/.ssh/$keyName 2>$null

                        # Copy public key
                        Write-Host "   Copying public key: $publicKeyPath" -ForegroundColor Gray
                        $publicKeyContent = Get-Content $publicKeyPath -Raw
                        $publicKeyContent | docker exec -i $containerInfo tee /home/vscode/.ssh/$keyName.pub 2>&1 | Out-Null

                        # Set correct permissions for public key (644)
                        docker exec $containerInfo chown vscode:vscode /home/vscode/.ssh/$keyName.pub 2>$null
                        docker exec $containerInfo chmod 644 /home/vscode/.ssh/$keyName.pub 2>$null

                        Write-Host "✅ SSH keys copied, configuring git signing..." -ForegroundColor Green

                        # Configure git to use SSH signing with the private key
                        devcontainer exec --workspace-folder $worktreePath git config --global gpg.format ssh
                        devcontainer exec --workspace-folder $worktreePath git config --global user.signingkey /home/vscode/.ssh/$keyName
                        devcontainer exec --workspace-folder $worktreePath git config --global commit.gpgsign true
                        devcontainer exec --workspace-folder $worktreePath git config --global tag.gpgsign true

                        Write-Host "✅ Git signing configured" -ForegroundColor Green
                    }
                    else {
                        Write-Host "⚠️  Could not copy SSH keys to container" -ForegroundColor Yellow
                    }
                }
                else {
                    Write-Host "⚠️  Could not find running container" -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "⚠️  SSH keys not found. Need both:" -ForegroundColor Yellow
                Write-Host "     Private: $privateKeyPath" -ForegroundColor Yellow
                Write-Host "     Public: $publicKeyPath" -ForegroundColor Yellow
            }
        }
    } # End of: if (-not $skipWorktreeSetup)

    Write-Host "`nStarting: $Command" -ForegroundColor Cyan

    # Connect to the container and run the command
    # Use try/finally to ensure git paths are reset when command exits
    try {
        $cmdArgs = @("exec", "--workspace-folder", $worktreePath, "bash", "-c", $Command)
        & devcontainer @cmdArgs
    }
    finally {
        # Reset git paths back to host paths
        Write-Host "`n🔧 Resetting .git paths for host..." -ForegroundColor Cyan

        # Reset worktree .git file to point to host path
        # (retry a few times in case file is briefly locked by container shutdown)
        $hostGitPath = Join-Path $env:MAIN_GIT_PATH "worktrees" $worktreeName
        $retries = 5
        $retryDelay = 1
        $success = $false

        for ($i = 0; $i -lt $retries; $i++) {
            try {
                Set-Content -Path $worktreeGitFile -Value "gitdir: $hostGitPath" -NoNewline -Encoding utf8NoBOM -ErrorAction Stop
                $success = $true
                break
            }
            catch {
                if ($i -lt ($retries - 1)) {
                    Write-Host "   Waiting for file lock to release... (attempt $($i+1)/$retries)" -ForegroundColor Gray
                    Start-Sleep -Seconds $retryDelay
                }
            }
        }

        if (-not $success) {
            Write-Host "⚠️  Could not reset .git file (still locked). You may need to:" -ForegroundColor Yellow
            Write-Host "   1. Wait a moment for container to fully stop" -ForegroundColor Gray
            Write-Host "   2. Manually edit: $worktreeGitFile" -ForegroundColor Gray
            Write-Host "   3. Set content to: gitdir: $hostGitPath" -ForegroundColor Gray
        }
        else {
            Write-Host "   Set .git to: $hostGitPath" -ForegroundColor Gray

            # Reset gitdir in main repo's worktree metadata to host path
            if (Test-Path $worktreeMetaGitdir) {
                try {
                    Set-Content -Path $worktreeMetaGitdir -Value $worktreePath -NoNewline -Encoding utf8NoBOM -ErrorAction Stop
                    Write-Host "   Set gitdir to: $worktreePath" -ForegroundColor Gray
                }
                catch {
                    Write-Host "⚠️  Could not reset gitdir file (still locked)" -ForegroundColor Yellow
                }
            }

            Write-Host "✅ Git paths restored for host" -ForegroundColor Green
        }
    }
}
