# Copyright 2026 James Casey
# SPDX-License-Identifier: Apache-2.0

function Remove-CopilotWorktree {
    <#
    .SYNOPSIS
        Stop and remove a git worktree and its devcontainer.

    .DESCRIPTION
        Removes a worktree that may have been used with devcontainers.

        This cmdlet:
        - Stops and removes the devcontainer for the worktree
        - Fixes any container path issues in .git file
        - Removes the worktree directory
        - Optionally deletes the branch

        Note: Path normalization is applied to handle git's forward slashes
        vs Docker's backslashes on Windows.

    .PARAMETER Branch
        The branch name of the worktree to remove (e.g., "feature-branch")

    .PARAMETER Force
        Force removal even if there are uncommitted changes

    .EXAMPLE
        Remove-CopilotWorktree feature-branch

    .EXAMPLE
        Remove-CopilotWorktree -Branch issue-123 -Force
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Branch,

        [switch]$Force
    )

    $ErrorActionPreference = "Stop"

    Write-Host "🛑 Stopping worktree for branch: $Branch" -ForegroundColor Cyan

    # Find main repo
    $mainRepo = Get-MainRepoRoot
    Write-Host "📁 Main repo: $mainRepo" -ForegroundColor Gray

    # Worktrees are in .worktrees/ subdirectory
    $worktreeRoot = Join-Path $mainRepo ".worktrees"

    # Work from main repo
    Push-Location $mainRepo
    try {
        # Find the worktree path
        $worktreePath = Find-WorktreeForBranch -BranchName $Branch -WorktreeRoot $worktreeRoot

        if (-not $worktreePath) {
            Write-Host "⚠️  No worktree found for branch: $Branch" -ForegroundColor Yellow
            Write-Host "   Checking for orphaned worktree metadata..." -ForegroundColor Gray

            # Check if there's orphaned metadata
            $worktreeMetaPath = Join-Path ".git" "worktrees" $Branch
            if (Test-Path $worktreeMetaPath) {
                Write-Host "🧹 Found orphaned metadata, cleaning up..." -ForegroundColor Yellow
                if ($PSCmdlet.ShouldProcess($worktreeMetaPath, "Remove orphaned worktree metadata")) {
                    Remove-Item -Recurse -Force $worktreeMetaPath
                    Write-Host "✅ Cleaned up orphaned worktree metadata" -ForegroundColor Green
                }
            }
            else {
                Write-Host "❌ No worktree or metadata found for: $Branch" -ForegroundColor Red
            }
            return
        }

        Write-Host "📂 Worktree path: $worktreePath" -ForegroundColor Gray

        # Show what branch is actually checked out (informational)
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

        # Stop devcontainer FIRST (before removing worktree to release file locks)
        if ($PSCmdlet.ShouldProcess($worktreePath, "Remove devcontainer")) {
            Remove-DevContainer -WorktreePath $worktreePath
        }

        # Run project-specific hook if it exists (for custom cleanup like volumes)
        $hookScript = Join-Path $worktreePath ".devcontainer\worktree-down-hook.ps1"
        if (Test-Path $hookScript) {
            Write-Host "🔧 Running project cleanup hook..." -ForegroundColor Cyan
            try {
                & $hookScript -WorktreePath $worktreePath -Branch $Branch -MainRepo $mainRepo
                if (-not $?) {
                    Write-Host "⚠️  Project cleanup hook reported failure" -ForegroundColor Yellow
                }
                else {
                    Write-Host "✅ Project cleanup hook completed" -ForegroundColor Green
                }
            }
            catch {
                Write-Host "⚠️  Project cleanup hook failed: $_" -ForegroundColor Yellow
            }
        }

        # Check if the .git file in the worktree needs fixing
        $gitFile = Join-Path $worktreePath ".git"
        if (Test-Path $gitFile -PathType Leaf) {
            $gitContent = Get-Content $gitFile -Raw

            # Check if it points to container path
            if ($gitContent -match "/workspaces/") {
                Write-Host "🔧 Fixing container path in .git file..." -ForegroundColor Yellow

                # Find the worktree name from the path
                if ($gitContent -match "worktrees/([^/\r\n]+)") {
                    $worktreeName = $matches[1]
                    $correctPath = Join-Path $mainRepo ".git" "worktrees" $worktreeName
                    $correctPath = $correctPath -replace "\\", "/"

                    Set-Content -Path $gitFile -Value "gitdir: $correctPath" -NoNewline
                    Write-Host "✅ Fixed .git to point to: $correctPath" -ForegroundColor Green
                }
            }
        }
        elseif (-not (Test-Path $gitFile)) {
            Write-Host "⚠️  No .git file found in worktree (may be corrupted)" -ForegroundColor Yellow
        }

        # Try standard worktree remove first
        if ($PSCmdlet.ShouldProcess($worktreePath, "Remove git worktree")) {
            $removeArgs = @("worktree", "remove", $worktreePath)
            if ($Force) {
                $removeArgs += "--force"
            }

            Write-Host "🗑️  Removing worktree..." -ForegroundColor Cyan
            $result = & git @removeArgs 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Worktree removed successfully" -ForegroundColor Green
            }
            elseif ($result -match "modified or untracked files") {
                Write-Host "❌ Worktree has uncommitted changes" -ForegroundColor Red
                Write-Host "   Use -Force to delete anyway, or commit/stash your changes first." -ForegroundColor Yellow
                return
            }
            else {
                Write-Host "⚠️  git worktree remove failed: $result" -ForegroundColor Yellow
                Write-Host "🔧 Attempting manual cleanup..." -ForegroundColor Cyan

                # Manual cleanup
                $worktreeMetaPath = Join-Path ".git" "worktrees" $Branch

                # Also try with the worktree directory name if different from branch
                $worktreeDirName = Split-Path $worktreePath -Leaf
                $worktreeMetaPathAlt = Join-Path ".git" "worktrees" $worktreeDirName

                # Remove metadata
                foreach ($metaPath in @($worktreeMetaPath, $worktreeMetaPathAlt)) {
                    if (Test-Path $metaPath) {
                        Write-Host "   Removing: $metaPath" -ForegroundColor Gray
                        Remove-Item -Recurse -Force $metaPath
                    }
                }

                # Remove worktree directory
                if (Test-Path $worktreePath) {
                    Write-Host "   Removing: $worktreePath" -ForegroundColor Gray
                    Remove-Item -Recurse -Force $worktreePath
                }

                # Prune stale entries
                git worktree prune

                Write-Host "✅ Manual cleanup complete" -ForegroundColor Green
            }
        }

        # Optionally delete the branch (skip prompts during -WhatIf)
        if (-not $WhatIfPreference) {
            Write-Host ""
            $deleteBranch = Read-Host "Delete local branch '$Branch'? (y/N)"
            if ($deleteBranch -eq 'y' -or $deleteBranch -eq 'Y') {
                if ($PSCmdlet.ShouldProcess($Branch, "Delete local branch")) {
                    # Update main branch to check against latest remote state
                    Write-Host "🔄 Updating main branch..." -ForegroundColor Cyan
                    git fetch origin main:main 2>$null
                    if ($LASTEXITCODE -ne 0) {
                        # Fallback if fast-forward fails
                        git fetch origin main 2>$null
                    }

                    git branch -d $Branch 2>$null
                    if ($LASTEXITCODE -ne 0) {
                        Write-Host "⚠️  Branch not fully merged. Force delete? (y/N)" -ForegroundColor Yellow
                        $forceDelete = Read-Host
                        if ($forceDelete -eq 'y' -or $forceDelete -eq 'Y') {
                            git branch -D $Branch
                        }
                    }
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "✅ Branch deleted" -ForegroundColor Green
                    }
                }
            }
        }
    }
    finally {
        Pop-Location
    }

    Write-Host "`n✨ Done!" -ForegroundColor Green
}
