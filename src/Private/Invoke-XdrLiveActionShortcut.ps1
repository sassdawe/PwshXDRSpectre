function Invoke-XdrLiveActionShortcut {
    <#
    .SYNOPSIS
    Executes a live dashboard action shortcut.

    .DESCRIPTION
    Processes incident and alert shortcut actions, updates pending workflow
    state, and writes status/confirmation messages.

    .PARAMETER Shortcut
    Shortcut key identifier.

    .PARAMETER Context
    Runtime context object.

    .PARAMETER SelectedIncident
    Currently selected incident.

    .PARAMETER SelectedAlert
    Currently selected alert.

    .PARAMETER TriageOptions
    Cached triage option payload.

    .PARAMETER PanelOrder
    Panel navigation order.

    .PARAMETER ActivePanel
    Active panel reference.

    .PARAMETER ActivePanelIndex
    Active panel index reference.

    .PARAMETER ActivePanelBeforeResolution
    Previous panel reference before resolution workflow.

    .PARAMETER PendingConfirmation
    Pending confirmation payload reference.

    .PARAMETER PendingTextInput
    Pending text input payload reference.

    .PARAMETER PendingIncidentResolution
    Pending incident resolution payload reference.

    .PARAMETER ActivePanelBeforeComment
    Previous panel reference before incident comment workflow.

    .PARAMETER PendingIncidentComment
    Pending incident comment workflow payload reference.

    .PARAMETER ModulePath
    Module path used by background jobs.

    .PARAMETER AlertsByIncidentId
    Alert cache map keyed by incident id.

    .PARAMETER AlertLoadJobsByIncidentId
    Running jobs map keyed by incident id.

    .PARAMETER SelectedAlertIdByIncidentId
    Last selected alert id map keyed by incident id.

    .PARAMETER SelectedAlertIndex
    Selected alert index reference.

    .OUTPUTS
    None

    .EXAMPLE
    Invoke-XdrLiveActionShortcut -Shortcut a -Context $context -SelectedIncident $selectedIncident -SelectedAlert $selectedAlert -TriageOptions $triageOptions -PanelOrder $panelOrder -ActivePanel ([ref]$activePanel) -ActivePanelIndex ([ref]$activePanelIndex) -ActivePanelBeforeResolution ([ref]$activePanelBeforeResolution) -PendingConfirmation ([ref]$pendingConfirmation) -PendingTextInput ([ref]$pendingTextInput) -PendingIncidentResolution ([ref]$pendingIncidentResolution) -ModulePath $modulePath -AlertsByIncidentId $alertsByIncidentId -AlertLoadJobsByIncidentId $alertLoadJobsByIncidentId -SelectedAlertIdByIncidentId $selectedAlertIdByIncidentId -SelectedAlertIndex ([ref]$selectedAlertIndex)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Shortcut,

        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter()]
        [object]$SelectedIncident,

        [Parameter()]
        [object]$SelectedAlert,

        [Parameter(Mandatory)]
        [object]$TriageOptions,

        [Parameter(Mandatory)]
        [string[]]$PanelOrder,

        [Parameter(Mandatory)]
        [ref]$ActivePanel,

        [Parameter(Mandatory)]
        [ref]$ActivePanelIndex,

        [Parameter(Mandatory)]
        [ref]$ActivePanelBeforeResolution,

        [Parameter(Mandatory)]
        [ref]$PendingConfirmation,

        [Parameter(Mandatory)]
        [ref]$PendingTextInput,

        [Parameter(Mandatory)]
        [ref]$PendingIncidentResolution,

        [Parameter()]
        [ref]$ActivePanelBeforeClassification,

        [Parameter()]
        [ref]$PendingIncidentClassification,

        [Parameter()]
        [ref]$ActivePanelBeforeComment,

        [Parameter()]
        [ref]$PendingIncidentComment,

        [Parameter(Mandatory)]
        [string]$ModulePath,

        [Parameter(Mandatory)]
        [hashtable]$AlertsByIncidentId,

        [Parameter(Mandatory)]
        [hashtable]$AlertLoadJobsByIncidentId,

        [Parameter(Mandatory)]
        [hashtable]$SelectedAlertIdByIncidentId,

        [Parameter(Mandatory)]
        [ref]$SelectedAlertIndex
    )

    switch ($Shortcut) {
        'l' {
            if (-not $SelectedIncident) {
                Set-LiveStatusMessage -Context $Context -Message 'No incident is selected for loading alerts.' -Level 'warning'
                break
            }

            $incidentId = [string]$SelectedIncident.IncidentId
            if (Restore-XdrLiveCachedAlertsForIncident -IncidentId $incidentId -AlertsByIncidentId $AlertsByIncidentId -Context $Context -SelectedAlertIdByIncidentId $SelectedAlertIdByIncidentId -SelectedAlert ([ref]$SelectedAlert) -SelectedAlertIndex $SelectedAlertIndex) {
                Set-LiveStatusMessage -Context $Context -Message 'Loaded alerts from cache.' -Level 'success'
            }
            elseif ($AlertLoadJobsByIncidentId.ContainsKey($incidentId)) {
                Set-LiveStatusMessage -Context $Context -Message 'Alerts are already loading in background...' -Level 'info'
            }
            elseif (Start-XdrLiveAlertLoadJob -Incident $SelectedIncident -ForceReload -ModulePath $ModulePath -Context $Context -AlertsByIncidentId $AlertsByIncidentId -AlertLoadJobsByIncidentId $AlertLoadJobsByIncidentId) {
                Set-LiveStatusMessage -Context $Context -Message 'Loading alerts in background...' -Level 'info'
            }
            else {
                Set-LiveStatusMessage -Context $Context -Message 'Unable to start alert loading for this incident.' -Level 'warning'
            }
        }
        'a' {
            $assignResult = Set-XdrIncidentTriage -Context $Context -IncidentId $SelectedIncident.IncidentId -AssignToMe
            Set-StatusFromResult -Context $Context -Result $assignResult
        }
        'u' {
            $clearResult = Set-XdrIncidentTriage -Context $Context -IncidentId $SelectedIncident.IncidentId -ClearAssignment
            if ($clearResult.Data -and $clearResult.Data.ConfirmationRequired) {
                $PendingConfirmation.Value = [pscustomobject]@{
                    ActionName = $clearResult.Data.ActionName
                    Prompt     = $clearResult.Data.Prompt
                    Execute    = { Set-XdrIncidentTriage -Context $Context -IncidentId $SelectedIncident.IncidentId -ClearAssignment -SkipConfirmation }
                }
            }
            Set-StatusFromResult -Context $Context -Result $clearResult -PendingMessage 'Confirmation required to clear the incident assignment.'
        }
        'o' {
            $activeResult = Set-XdrIncidentTriage -Context $Context -IncidentId $SelectedIncident.IncidentId -Status 'Active'
            Set-StatusFromResult -Context $Context -Result $activeResult
        }
        'i' {
            $progressResult = Set-XdrIncidentTriage -Context $Context -IncidentId $SelectedIncident.IncidentId -Status 'In progress'
            Set-StatusFromResult -Context $Context -Result $progressResult
        }
        'r' {
            $classificationChoices = @($TriageOptions.IncidentClassifications)
            if ($classificationChoices.Count -eq 0) {
                Set-LiveStatusMessage -Context $Context -Message 'No incident classification options are configured.' -Level 'warning'
                break
            }

            $determinationChoices = @($TriageOptions.IncidentDeterminations)
            if ($determinationChoices.Count -eq 0) {
                Set-LiveStatusMessage -Context $Context -Message 'No incident determination options are configured.' -Level 'warning'
                break
            }

            $classificationIndex = 0
            $currentClassification = [string]$SelectedIncident.Classification
            if (-not [string]::IsNullOrWhiteSpace($currentClassification)) {
                for ($idx = 0; $idx -lt $classificationChoices.Count; $idx++) {
                    $option = $classificationChoices[$idx]
                    if ([string]$option.graphValue -eq $currentClassification -or [string]$option.label -eq $currentClassification) {
                        $classificationIndex = $idx
                        break
                    }
                }
            }

            $determinationIndex = 0
            $currentDetermination = [string]$SelectedIncident.Determination
            if (-not [string]::IsNullOrWhiteSpace($currentDetermination)) {
                for ($idx = 0; $idx -lt $determinationChoices.Count; $idx++) {
                    $option = $determinationChoices[$idx]
                    if ([string]$option.graphValue -eq $currentDetermination -or [string]$option.label -eq $currentDetermination) {
                        $determinationIndex = $idx
                        break
                    }
                }
            }

            $ActivePanelBeforeResolution.Value = $ActivePanel.Value
            $ActivePanel.Value = 'action_status'
            $ActivePanelIndex.Value = [array]::IndexOf($PanelOrder, 'action_status')
            $Context.Selection.Panel = $ActivePanel.Value

            $PendingTextInput.Value = $null
            $PendingIncidentResolution.Value = [pscustomobject]@{
                Step                  = 'classification'
                ClassificationOptions = $classificationChoices
                ClassificationIndex   = $classificationIndex
                DeterminationOptions  = $determinationChoices
                DeterminationIndex    = $determinationIndex
                ResolvingComment      = ''
            }
        }
        'k' {
            if (-not $SelectedIncident) {
                Set-LiveStatusMessage -Context $Context -Message 'No incident is selected for this shortcut.' -Level 'warning'
                break
            }

            $classificationChoices = @($TriageOptions.IncidentClassifications)
            if ($classificationChoices.Count -eq 0) {
                Set-LiveStatusMessage -Context $Context -Message 'No incident classification options are configured.' -Level 'warning'
                break
            }

            $currentClassification = [string]$SelectedIncident.Classification
            $currentIndex = -1
            for ($idx = 0; $idx -lt $classificationChoices.Count; $idx++) {
                $option = $classificationChoices[$idx]
                if ([string]$option.graphValue -eq $currentClassification -or [string]$option.label -eq $currentClassification) {
                    $currentIndex = $idx
                    break
                }
            }

            if ($currentIndex -lt 0) {
                $currentIndex = 0
            }

            $canOpenPicker = $PSBoundParameters.ContainsKey('PendingIncidentClassification') -and $null -ne $PendingIncidentClassification
            if ($canOpenPicker) {
                if ($PSBoundParameters.ContainsKey('ActivePanelBeforeClassification') -and $null -ne $ActivePanelBeforeClassification) {
                    $ActivePanelBeforeClassification.Value = $ActivePanel.Value
                }

                $ActivePanel.Value = 'action_status'
                $ActivePanelIndex.Value = [array]::IndexOf($PanelOrder, 'action_status')
                $Context.Selection.Panel = $ActivePanel.Value

                $PendingTextInput.Value = $null
                $PendingIncidentResolution.Value = $null
                $PendingIncidentClassification.Value = [pscustomobject]@{
                    Step                  = 'classification'
                    ClassificationOptions = $classificationChoices
                    ClassificationIndex   = $currentIndex
                }
            }
            else {
                # Compatibility path for callers that do not supply picker refs.
                $nextIndex = ($currentIndex + 1) % $classificationChoices.Count
                $nextClassificationLabel = [string]$classificationChoices[$nextIndex].label
                $classificationResult = Set-XdrIncidentTriage -Context $Context -IncidentId $SelectedIncident.IncidentId -Classification $nextClassificationLabel
                Set-StatusFromResult -Context $Context -Result $classificationResult
            }
        }
        'c' {
            if (-not $SelectedIncident) {
                Set-LiveStatusMessage -Context $Context -Message 'No incident is selected for this shortcut.' -Level 'warning'
                break
            }

            $canOpenWizard = $PSBoundParameters.ContainsKey('PendingIncidentComment') -and $null -ne $PendingIncidentComment
            if (-not $canOpenWizard) {
                Set-LiveStatusMessage -Context $Context -Message 'Comment workflow is unavailable in this context.' -Level 'warning'
                break
            }

            if ($PSBoundParameters.ContainsKey('ActivePanelBeforeComment') -and $null -ne $ActivePanelBeforeComment) {
                $ActivePanelBeforeComment.Value = $ActivePanel.Value
            }

            $ActivePanel.Value = 'action_status'
            $ActivePanelIndex.Value = [array]::IndexOf($PanelOrder, 'action_status')
            $Context.Selection.Panel = $ActivePanel.Value

            $PendingTextInput.Value = $null
            $PendingIncidentResolution.Value = $null
            if ($PSBoundParameters.ContainsKey('PendingIncidentClassification') -and $null -ne $PendingIncidentClassification) {
                $PendingIncidentClassification.Value = $null
            }
            $PendingIncidentComment.Value = [pscustomobject]@{
                Step    = 'comment'
                Comment = ''
            }
        }
        'n' {
            if (-not $SelectedAlert) {
                Set-LiveStatusMessage -Context $Context -Message 'No alert is selected for this shortcut.' -Level 'warning'
            }
            else {
                $alertNewResult = Set-XdrAlertStatus -Context $Context -AlertId $SelectedAlert.AlertId -Status 'New'
                if ($alertNewResult.Data -and $alertNewResult.Data.ConfirmationRequired) {
                    $PendingConfirmation.Value = [pscustomobject]@{
                        ActionName = $alertNewResult.Data.ActionName
                        Prompt     = $alertNewResult.Data.Prompt
                        Execute    = { Set-XdrAlertStatus -Context $Context -AlertId $SelectedAlert.AlertId -Status 'New' -SkipConfirmation }
                    }
                }
                Set-StatusFromResult -Context $Context -Result $alertNewResult -PendingMessage 'Confirmation required to reopen the alert.'
            }
        }
        'p' {
            if (-not $SelectedAlert) {
                Set-LiveStatusMessage -Context $Context -Message 'No alert is selected for this shortcut.' -Level 'warning'
            }
            else {
                $alertProgressResult = Set-XdrAlertStatus -Context $Context -AlertId $SelectedAlert.AlertId -Status 'In progress'
                Set-StatusFromResult -Context $Context -Result $alertProgressResult
            }
        }
        'm' {
            if (-not $SelectedAlert) {
                Set-LiveStatusMessage -Context $Context -Message 'No alert is selected for this shortcut.' -Level 'warning'
            }
            else {
                $alertResolveResult = Set-XdrAlertStatus -Context $Context -AlertId $SelectedAlert.AlertId -Status 'Resolved'
                if ($alertResolveResult.Data -and $alertResolveResult.Data.ConfirmationRequired) {
                    $PendingConfirmation.Value = [pscustomobject]@{
                        ActionName = $alertResolveResult.Data.ActionName
                        Prompt     = $alertResolveResult.Data.Prompt
                        Execute    = { Set-XdrAlertStatus -Context $Context -AlertId $SelectedAlert.AlertId -Status 'Resolved' -SkipConfirmation }
                    }
                }
                Set-StatusFromResult -Context $Context -Result $alertResolveResult -PendingMessage 'Confirmation required to resolve the alert.'
            }
        }
    }
}
