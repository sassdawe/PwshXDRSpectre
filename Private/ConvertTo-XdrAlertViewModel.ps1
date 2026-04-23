function ConvertTo-XdrAlertViewModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Alert,

        [Parameter(Mandatory)]
        [string]$IncidentId
    )

    [pscustomobject]@{
        AlertId          = $Alert.Id
        Title            = $Alert.Title
        Status           = $Alert.Status
        Severity         = $Alert.Severity
        CreatedDateTime  = $Alert.CreatedDateTime
        AlertWebUrl      = $Alert.AlertWebUrl
        IncidentId       = $IncidentId
        RawObject        = $Alert
    }
}