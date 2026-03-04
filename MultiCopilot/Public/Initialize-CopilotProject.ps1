# Copyright 2026 James Casey
# SPDX-License-Identifier: Apache-2.0

function Initialize-CopilotProject {
    <#
    .SYNOPSIS
        Scaffold devcontainer template files into a project directory.

    .DESCRIPTION
        Copies the MultiCopilot .devcontainer/ template files and supporting
        scripts into the target project directory.  This replaces the manual
        "copy these files" step from the old workflow.

        The target must be a git repository (must contain a .git directory).
        If .devcontainer/ already exists use -Force to overwrite.

    .PARAMETER Path
        Target project directory.  Defaults to the current directory.

    .PARAMETER Force
        Overwrite existing .devcontainer/ files if they already exist.

    .EXAMPLE
        Initialize-CopilotProject

        Scaffold template files into the current directory.

    .EXAMPLE
        Initialize-CopilotProject -Path C:\Projects\my-app

        Scaffold template files into the specified project directory.

    .EXAMPLE
        Initialize-CopilotProject -Force

        Overwrite existing .devcontainer/ files in the current directory.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [string]$Path = (Get-Location).Path,

        [switch]$Force
    )

    $ErrorActionPreference = "Stop"

    $targetPath = Resolve-Path $Path -ErrorAction Stop | Select-Object -ExpandProperty Path
    $templateRoot = Join-Path $PSScriptRoot ".." "Templates"
    $templateRoot = Resolve-Path $templateRoot | Select-Object -ExpandProperty Path

    # Validate target is a git repository
    $gitDir = Join-Path $targetPath ".git"
    if (-not (Test-Path $gitDir)) {
        Write-Error "Target directory is not a git repository: $targetPath"
        return
    }

    # Check for existing .devcontainer/
    $devcontainerDir = Join-Path $targetPath ".devcontainer"
    if ((Test-Path $devcontainerDir) -and -not $Force) {
        Write-Warning ".devcontainer/ already exists in $targetPath. Use -Force to overwrite."
        return
    }

    $createdFiles = @()

    # Copy .devcontainer/ directory
    $templateDevcontainer = Join-Path $templateRoot ".devcontainer"
    if ($PSCmdlet.ShouldProcess($devcontainerDir, "Copy .devcontainer/ template files")) {
        if (-not (Test-Path $devcontainerDir)) {
            New-Item -ItemType Directory -Path $devcontainerDir -Force | Out-Null
        }
        foreach ($file in Get-ChildItem -Path $templateDevcontainer -File) {
            $dest = Join-Path $devcontainerDir $file.Name
            Copy-Item -Path $file.FullName -Destination $dest -Force
            $createdFiles += ".devcontainer/$($file.Name)"
        }
    }

    # Copy smoke-test.sh to scripts/smoke-test.sh
    $templateSmokeTest = Join-Path $templateRoot "smoke-test.sh"
    $scriptsDir = Join-Path $targetPath "scripts"
    $destSmokeTest = Join-Path $scriptsDir "smoke-test.sh"
    if ($PSCmdlet.ShouldProcess($destSmokeTest, "Copy smoke-test.sh")) {
        if (-not (Test-Path $scriptsDir)) {
            New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
        }
        Copy-Item -Path $templateSmokeTest -Destination $destSmokeTest -Force
        $createdFiles += "scripts/smoke-test.sh"
    }

    # Merge .gitattributes entries
    $templateGitattributes = Join-Path $templateRoot ".gitattributes"
    $destGitattributes = Join-Path $targetPath ".gitattributes"
    if ($PSCmdlet.ShouldProcess($destGitattributes, "Merge .gitattributes entries")) {
        $templateLines = Get-Content $templateGitattributes
        if (Test-Path $destGitattributes) {
            $existingContent = Get-Content $destGitattributes -Raw
            $linesToAdd = @()
            foreach ($line in $templateLines) {
                $trimmed = $line.Trim()
                if ($trimmed -eq "" -or $trimmed.StartsWith("#")) { continue }
                if ($existingContent -notmatch [regex]::Escape($trimmed)) {
                    $linesToAdd += $line
                }
            }
            if ($linesToAdd.Count -gt 0) {
                $separator = "`n`n# Added by MultiCopilot`n"
                $addition = $separator + ($linesToAdd -join "`n") + "`n"
                Add-Content -Path $destGitattributes -Value $addition -NoNewline
                $createdFiles += ".gitattributes (merged)"
            }
            else {
                $createdFiles += ".gitattributes (no changes needed)"
            }
        }
        else {
            Copy-Item -Path $templateGitattributes -Destination $destGitattributes
            $createdFiles += ".gitattributes"
        }
    }

    # Add .worktrees/ to .gitignore if not already present
    $gitignorePath = Join-Path $targetPath ".gitignore"
    if ($PSCmdlet.ShouldProcess($gitignorePath, "Add .worktrees/ to .gitignore")) {
        $worktreeEntry = ".worktrees/"
        $needsAdd = $true
        if (Test-Path $gitignorePath) {
            $gitignoreContent = Get-Content $gitignorePath -Raw
            if ($gitignoreContent -match [regex]::Escape($worktreeEntry)) {
                $needsAdd = $false
            }
        }
        if ($needsAdd) {
            if (Test-Path $gitignorePath) {
                Add-Content -Path $gitignorePath -Value "`n# MultiCopilot worktrees`n$worktreeEntry`n"
            }
            else {
                Set-Content -Path $gitignorePath -Value "# MultiCopilot worktrees`n$worktreeEntry`n"
            }
            $createdFiles += ".gitignore (added .worktrees/)"
        }
    }

    # Summary
    Write-Host ""
    Write-Host "✅ Project initialized for MultiCopilot" -ForegroundColor Green
    Write-Host ""
    Write-Host "Files created/updated:" -ForegroundColor Cyan
    foreach ($file in $createdFiles) {
        Write-Host "   $file" -ForegroundColor Gray
    }
    Write-Host ""
}
