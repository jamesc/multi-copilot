# Copyright 2026 James Casey
# SPDX-License-Identifier: Apache-2.0

# Shared helper functions for MultiCopilot cmdlets

function Get-MainRepoRoot {
    <#
    .SYNOPSIS
        Find the main repo root (where .git is a directory, not a file).
    #>
    $current = Get-Location

    $gitPath = Join-Path $current ".git"

    if (Test-Path $gitPath -PathType Container) {
        return $current.Path
    }
    elseif (Test-Path $gitPath -PathType Leaf) {
        $gitContent = Get-Content $gitPath -Raw
        if ($gitContent -match "gitdir:\s*(.+)") {
            $gitDir = $matches[1].Trim()
            # gitDir points to .git/worktrees/name, go up to .git then to repo
            $mainGit = Split-Path (Split-Path $gitDir -Parent) -Parent
            return Split-Path $mainGit -Parent
        }
    }

    $gitRoot = git rev-parse --show-toplevel 2>$null
    if ($gitRoot) {
        return $gitRoot
    }

    throw "Could not find git repository root"
}

function Get-DefaultBranch {
    <#
    .SYNOPSIS
        Detect the default branch (main or master).
    #>
    $remoteBranch = git symbolic-ref refs/remotes/origin/HEAD 2>$null
    if ($remoteBranch -match "refs/remotes/origin/(.+)") {
        return $matches[1]
    }
    if (git rev-parse --verify main 2>$null) {
        return "main"
    }
    return "master"
}

function Test-BranchExists {
    <#
    .SYNOPSIS
        Check if a branch exists locally or on remote.
    #>
    param([string]$BranchName)

    $local = git branch --list $BranchName 2>$null
    if ($local) { return $true }

    $remote = git branch -r --list "origin/$BranchName" 2>$null
    if ($remote) { return $true }

    return $false
}

function Find-WorktreeForBranch {
    <#
    .SYNOPSIS
        Find the worktree path for a branch by matching directory name.
    #>
    param(
        [string]$BranchName,
        [string]$WorktreeRoot
    )

    $dirName = $BranchName -replace '/', '-'
    $expectedPath = Join-Path $WorktreeRoot $dirName

    $worktrees = git worktree list --porcelain 2>$null
    $wtPath = $null
    foreach ($line in $worktrees) {
        if ($line -match "^worktree\s+(.+)") {
            $wtPath = $matches[1]

            # Convert container path to host path if needed
            if ($wtPath -match "^/workspaces/(.+)$") {
                $folderName = $matches[1]
                $wtPath = Join-Path $WorktreeRoot $folderName
            }

            if ($wtPath -eq $expectedPath) {
                return $wtPath
            }
        }
    }
    return $null
}

function Get-ProjectName {
    <#
    .SYNOPSIS
        Get project name from repository root folder name.
    #>
    param([string]$RepoPath)
    return Split-Path $RepoPath -Leaf
}

function Test-ContainerRunning {
    <#
    .SYNOPSIS
        Check if a devcontainer is running for a worktree path.
    #>
    param([string]$WorktreePath)

    $containerList = docker ps --filter "label=devcontainer.local_folder=$WorktreePath" --format "{{.ID}}" 2>$null
    return ($containerList -and $containerList.Trim() -ne "")
}

function Get-ContainerStatus {
    <#
    .SYNOPSIS
        Get container status for a worktree by name.
    #>
    param([string]$WorktreeName)

    $allContainers = docker ps -a --format '{{.ID}}|{{.Label "git.worktree"}}|{{.Label "devcontainer.local_folder"}}|{{.Status}}' 2>$null
    foreach ($line in $allContainers) {
        if (-not $line) { continue }

        $parts = $line -split '\|'
        $id = $parts[0]
        $worktreeLabel = $parts[1]
        $localFolder = $parts[2]
        $status = $parts[3]

        if ($worktreeLabel -eq $WorktreeName) {
            if ($status -match "^Up") {
                return "🟢 Running"
            } else {
                return "🔴 Stopped"
            }
        }

        if ($localFolder) {
            $labelName = Split-Path -Leaf $localFolder
            if ($labelName -eq $WorktreeName) {
                if ($status -match "^Up") {
                    return "🟢 Running"
                } else {
                    return "🔴 Stopped"
                }
            }
        }
    }

    return "⚪ No container"
}

function Remove-DevContainer {
    <#
    .SYNOPSIS
        Stop and remove devcontainer(s) for a worktree path.
    #>
    param([string]$WorktreePath)

    $folderName = Split-Path $WorktreePath -Leaf

    $allContainers = docker ps -a --format '{{.ID}}' 2>$null
    $containers = @()
    foreach ($id in $allContainers) {
        if (-not $id) { continue }

        $worktreeLabel = docker inspect --format '{{index .Config.Labels "git.worktree"}}' $id 2>$null
        if ($worktreeLabel -eq $folderName) {
            $containerName = docker inspect --format '{{.Name}}' $id 2>$null
            $containers += "$id`t$containerName"
            continue
        }

        $labelPath = docker inspect --format '{{index .Config.Labels "devcontainer.local_folder"}}' $id 2>$null
        if ($labelPath) {
            $labelFolderName = Split-Path $labelPath -Leaf
            if ($labelFolderName -eq $folderName) {
                $containerName = docker inspect --format '{{.Name}}' $id 2>$null
                $containers += "$id`t$containerName"
            }
        }
    }

    if ($containers) {
        Write-Host "🐳 Found devcontainer(s) for $folderName" -ForegroundColor Cyan
        foreach ($container in $containers) {
            $parts = $container -split "\t"
            $containerId = $parts[0]
            $containerName = $parts[1]

            Write-Host "   Stopping: $containerName" -ForegroundColor Gray
            docker stop $containerId 2>$null | Out-Null

            Write-Host "   Removing: $containerName" -ForegroundColor Gray
            docker rm $containerId 2>$null | Out-Null
        }
        Write-Host "✅ Devcontainer(s) removed" -ForegroundColor Green
    }
    else {
        Write-Host "ℹ️  No devcontainer found for $folderName" -ForegroundColor Gray
    }
}

function Invoke-WorktreeUpHook {
    <#
    .SYNOPSIS
        Run project-specific setup hook inside container if it exists.
    #>
    param([string]$WorktreePath)

    $upHookScript = Join-Path $WorktreePath ".devcontainer" "worktree-up-hook.sh"
    if (Test-Path $upHookScript) {
        Write-Host "🔧 Running project setup hook..." -ForegroundColor Cyan
        $hookOutput = & devcontainer exec --workspace-folder $WorktreePath bash .devcontainer/worktree-up-hook.sh 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Project setup hook completed" -ForegroundColor Green
        }
        else {
            Write-Host "⚠️  Project setup hook failed" -ForegroundColor Yellow
            if ($hookOutput) {
                Write-Host "Hook output:" -ForegroundColor DarkYellow
                Write-Host $hookOutput
            }
        }
    }
}
