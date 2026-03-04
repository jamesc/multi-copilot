# Copyright 2026 James Casey
# SPDX-License-Identifier: Apache-2.0

# MultiCopilot Module Loader
# Dot-source all private helpers and public cmdlets

$ModuleRoot = $PSScriptRoot

# Import private helpers
foreach ($file in Get-ChildItem -Path "$ModuleRoot/Private" -Filter '*.ps1' -ErrorAction SilentlyContinue) {
    . $file.FullName
}

# Import public cmdlets
foreach ($file in Get-ChildItem -Path "$ModuleRoot/Public" -Filter '*.ps1' -ErrorAction SilentlyContinue) {
    . $file.FullName
}

# Export only public functions
Export-ModuleMember -Function @(
    'Initialize-CopilotProject'
    'New-CopilotWorktree'
    'Remove-CopilotWorktree'
    'Get-CopilotWorktree'
    'Clear-CopilotWorktree'
)
