# Copyright 2026 James Casey
# SPDX-License-Identifier: Apache-2.0

@{
    RootModule        = 'MultiCopilot.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'a3c8f1e2-7d4b-4a9e-b6c5-1f2e3d4a5b6c'
    Author            = 'James Casey'
    CompanyName       = ''
    Copyright         = 'Copyright 2026 James Casey. Apache-2.0 license.'
    Description       = 'Run multiple parallel GitHub Copilot CLI sessions using git worktrees and devcontainers.'

    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Initialize-CopilotProject'
        'New-CopilotWorktree'
        'Remove-CopilotWorktree'
        'Get-CopilotWorktree'
        'Clear-CopilotWorktree'
    )

    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('copilot', 'devcontainer', 'worktree', 'git', 'parallel')
            LicenseUri   = 'https://github.com/jamesc/multi-copilot/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/jamesc/multi-copilot'
        }
    }
}
