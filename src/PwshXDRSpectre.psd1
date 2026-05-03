@{
    RootModule        = 'PwshXDRSpectre.psm1'
    ModuleVersion     = '0.2.0'
    GUID              = '5f7f5f28-74c4-4d6e-9f54-93f6c6f8d3d1'
    Author            = 'David Sass'
    CompanyName       = 'Kolislab'
    Copyright         = '(c) David Sass. All rights reserved.'
    Description       = 'Terminal UI and analyst operations module for Microsoft Defender XDR powered by PwshSpectreConsole.'

    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')

    RequiredModules   = @(
        'PwshSpectreConsole',
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Security'
    )

    FunctionsToExport = @(
        'Connect-XdrSession',
        'Get-XdrAlerts',
        'Get-XdrIncidents',
        'Get-XdrTriageOptions',
        'Set-XdrAlertStatus',
        'Set-XdrIncidentAssignment',
        'Set-XdrIncidentTriage',
        'Start-PwshXdrLiveDashboard'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags       = @('DefenderXDR', 'MicrosoftGraph', 'Security', 'TUI', 'PwshSpectreConsole')
            ProjectUri = 'https://github.com/sassdawe/PwshXDRSpectre'
            LicenseUri = 'https://github.com/sassdawe/PwshXDRSpectre/blob/main/LICENSE'
            Prerelease = ''
        }
    }
}