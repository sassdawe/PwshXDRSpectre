function Get-XdrWorkflowCatalog {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = (Join-Path -Path $PSScriptRoot -ChildPath '../../workflows')
    )

    if (-not (Test-Path -Path $Path -PathType Container)) {
        throw "Workflow catalog folder not found: $Path"
    }

    $workflowFiles = @(Get-ChildItem -Path $Path -Filter '*.json' -File -ErrorAction Stop | Sort-Object -Property Name)
    if ($workflowFiles.Count -eq 0) {
        return @()
    }

    $catalog = @()
    foreach ($workflowFile in $workflowFiles) {
        try {
            $workflowDefinition = Get-Content -Path $workflowFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Failed to parse workflow catalog file '$($workflowFile.Name)': $($_.Exception.Message)"
        }

        $catalog += $workflowDefinition
    }

    for ($index = 0; $index -lt $catalog.Count; $index++) {
        Test-XdrWorkflowSchema -Workflow $catalog[$index] -Catalog $catalog -Source $workflowFiles[$index].Name | Out-Null
    }

    return @($catalog)
}
