function Sync-XdrSelectedWorkflow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(Mandatory)]
        [ref]$SelectedWorkflowIndex,

        [Parameter(Mandatory)]
        [ref]$SelectedWorkflowStepIndex
    )

    $matches = @($Context.Data.Workflows)
    if ($matches.Count -eq 0) {
        $SelectedWorkflowIndex.Value = 0
        $SelectedWorkflowStepIndex.Value = 0
        $Context.Selection.Workflow = $null
        $Context.Selection.WorkflowStep = $null
        return
    }

    $SelectedWorkflowIndex.Value = [Math]::Min([Math]::Max([int]$SelectedWorkflowIndex.Value, 0), $matches.Count - 1)
    $selectedWorkflowMatch = $matches[$SelectedWorkflowIndex.Value]
    $steps = @($selectedWorkflowMatch.Workflow.steps)
    $SelectedWorkflowStepIndex.Value = [Math]::Min([Math]::Max([int]$SelectedWorkflowStepIndex.Value, 0), [Math]::Max(0, $steps.Count - 1))
    $Context.Selection.Workflow = $selectedWorkflowMatch
    $Context.Selection.WorkflowStep = if ($steps.Count -gt 0) { $steps[$SelectedWorkflowStepIndex.Value] } else { $null }
}
