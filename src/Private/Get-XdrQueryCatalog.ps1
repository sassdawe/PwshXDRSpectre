function Get-XdrQueryCatalog {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path = (Join-Path -Path $PSScriptRoot -ChildPath '../../queries')
    )

    if (-not (Test-Path -Path $Path -PathType Container)) {
        throw "Query catalog folder not found: $Path"
    }

    $queryFiles = @(Get-ChildItem -Path $Path -Filter '*.json' -File -ErrorAction Stop | Sort-Object -Property Name)
    if ($queryFiles.Count -eq 0) {
        return @()
    }

    $catalog = @()
    foreach ($queryFile in $queryFiles) {
        try {
            $queryDefinition = Get-Content -Path $queryFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Failed to parse query catalog file '$($queryFile.Name)': $($_.Exception.Message)"
        }

        $catalog += $queryDefinition
    }

    for ($index = 0; $index -lt $catalog.Count; $index++) {
        Test-XdrQuerySchema -Query $catalog[$index] -Catalog $catalog -Source $queryFiles[$index].Name | Out-Null
    }

    return @($catalog)
}