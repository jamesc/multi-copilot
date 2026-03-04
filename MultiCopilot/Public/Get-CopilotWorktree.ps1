# Copyright 2026 James Casey
# SPDX-License-Identifier: Apache-2.0

function Get-CopilotWorktree {
    <#
    .SYNOPSIS
        Show status of all git worktrees and their devcontainers.

    .DESCRIPTION
        Lists all worktrees in the repository and shows which ones have
        running or stopped devcontainers.

    .EXAMPLE
        Get-CopilotWorktree
    #>
    [CmdletBinding()]
    param()

    $ErrorActionPreference = "Stop"

    # Main logic
    $mainRepo = Get-MainRepoRoot
    $projectName = Split-Path $mainRepo -Leaf

    Write-Host "📂 Worktree Status for: $projectName" -ForegroundColor Cyan
    Write-Host ""

    # Get all worktrees
    Push-Location $mainRepo
    try {
        $worktrees = git worktree list --porcelain 2>$null

        $currentWorktree = $null
        $currentBranch = $null
        $results = @()

        foreach ($line in $worktrees) {
            if ($line -match "^worktree\s+(.+)") {
                # New worktree entry - save previous if exists
                if ($currentWorktree) {
                    $worktreeName = Split-Path $currentWorktree -Leaf
                    $normalizedWorktree = $currentWorktree -replace '/', '\'
                    $normalizedMain = $mainRepo -replace '/', '\'
                    $isMain = $normalizedWorktree -eq $normalizedMain

                    $results += @{
                        Path = $currentWorktree
                        Name = $worktreeName
                        Branch = if ($currentBranch) { $currentBranch } else { "(detached)" }
                        IsMain = $isMain
                        Container = if ($isMain) { "-" } else { Get-ContainerStatus -WorktreeName $worktreeName }
                    }
                }
                $currentWorktree = $matches[1]
                $currentBranch = $null
            }
            elseif ($line -match "^branch\s+refs/heads/(.+)") {
                $currentBranch = $matches[1]
            }
        }

        # Don't forget the last entry
        if ($currentWorktree) {
            $worktreeName = Split-Path $currentWorktree -Leaf
            $normalizedWorktree = $currentWorktree -replace '/', '\'
            $normalizedMain = $mainRepo -replace '/', '\'
            $isMain = $normalizedWorktree -eq $normalizedMain

            $results += @{
                Path = $currentWorktree
                Name = $worktreeName
                Branch = if ($currentBranch) { $currentBranch } else { "(detached)" }
                IsMain = $isMain
                Container = if ($isMain) { "-" } else { Get-ContainerStatus -WorktreeName $worktreeName }
            }
        }

        # Display results
        if ($results.Count -eq 0) {
            Write-Host "No worktrees found." -ForegroundColor Gray
        }
        else {
            # Header
            Write-Host ("{0,-20} {1,-20} {2}" -f "BRANCH", "WORKTREE", "CONTAINER") -ForegroundColor White
            Write-Host ("{0,-20} {1,-20} {2}" -f "------", "--------", "---------") -ForegroundColor DarkGray

            foreach ($wt in $results) {
                $branchDisplay = $wt.Branch
                $nameDisplay = if ($wt.IsMain) { "(main repo)" } else { $wt.Name }
                $containerDisplay = $wt.Container

                $branchColor = if ($wt.IsMain) { "DarkGray" } else { "Yellow" }

                Write-Host ("{0,-20}" -f $branchDisplay) -ForegroundColor $branchColor -NoNewline
                Write-Host (" {0,-20}" -f $nameDisplay) -ForegroundColor Gray -NoNewline
                Write-Host (" {0}" -f $containerDisplay)
            }
        }

        Write-Host ""
    }
    finally {
        Pop-Location
    }
}
