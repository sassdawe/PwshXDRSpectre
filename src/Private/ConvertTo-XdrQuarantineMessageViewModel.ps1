function ConvertTo-XdrQuarantineMessageViewModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Message
    )

    process {
        $additionalProperties = if ($Message.PSObject.Properties.Name -contains 'AdditionalProperties') { $Message.AdditionalProperties } else { $null }

        function Get-MessageProperty {
            param(
                [Parameter(Mandatory)]
                [string[]]$Name
            )

            foreach ($candidate in $Name) {
                if ($Message.PSObject.Properties.Name -contains $candidate -and $null -ne $Message.$candidate) {
                    return $Message.$candidate
                }

                if ($additionalProperties -and $additionalProperties.ContainsKey($candidate) -and $null -ne $additionalProperties[$candidate]) {
                    return $additionalProperties[$candidate]
                }
            }

            return $null
        }

        [pscustomobject]@{
            Identity            = [string](Get-MessageProperty -Name @('Identity', 'QuarantineMessageIdentity'))
            QuarantineMessageId = [string](Get-MessageProperty -Name @('QuarantineMessageId', 'MessageId', 'InternetMessageId'))
            SenderAddress       = [string](Get-MessageProperty -Name @('SenderAddress', 'Sender'))
            RecipientAddress    = [string](Get-MessageProperty -Name @('RecipientAddress', 'RecipientAddressList', 'Recipient'))
            Subject             = [string](Get-MessageProperty -Name @('Subject'))
            QuarantineType      = [string](Get-MessageProperty -Name @('QuarantineType', 'QuarantineTypes', 'Type'))
            ReleaseStatus       = [string](Get-MessageProperty -Name @('ReleaseStatus'))
            ReceivedTime        = Get-MessageProperty -Name @('ReceivedTime', 'Received')
            Expires             = Get-MessageProperty -Name @('Expires', 'ExpiresTime')
            Raw                 = $Message
        }
    }
}
