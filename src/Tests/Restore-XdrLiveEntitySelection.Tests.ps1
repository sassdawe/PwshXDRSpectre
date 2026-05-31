BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Restore-XdrLiveEntitySelection' {
    It 'restores the matching entity and index from a selection key' {
        InModuleScope PwshXDRSpectre {
            $entities = @(
                [pscustomobject]@{ EntityType = 'Device'; DisplayName = 'device-1'; AlertId = 'a-1'; DeviceId = 'd-1'; Source = 'AlertEvidence' },
                [pscustomobject]@{ EntityType = 'User'; DisplayName = 'user@contoso.com'; AlertId = 'a-2'; UserId = 'u-2'; UserPrincipalName = 'user@contoso.com'; Source = 'AlertEvidence' }
            )
            $context = [pscustomobject]@{
                Data      = [pscustomobject]@{ Entities = $entities }
                Selection = [pscustomobject]@{ Entity = $null }
            }
            $selectedEntity = $null
            $selectedEntityIndex = 0
            $selectionKey = Get-XdrEntitySelectionKey -Entity $entities[1]

            $result = Restore-XdrLiveEntitySelection -Context $context -EntitySelectionKey $selectionKey -SelectedEntity ([ref]$selectedEntity) -SelectedEntityIndex ([ref]$selectedEntityIndex)

            $result | Should -BeTrue
            $selectedEntityIndex | Should -Be 1
            $selectedEntity.DisplayName | Should -Be 'user@contoso.com'
            $context.Selection.Entity.DisplayName | Should -Be 'user@contoso.com'
        }
    }

    It 'clears selection when there are no entities' {
        InModuleScope PwshXDRSpectre {
            $context = [pscustomobject]@{
                Data      = [pscustomobject]@{ Entities = @() }
                Selection = [pscustomobject]@{ Entity = [pscustomobject]@{ DisplayName = 'stale' } }
            }
            $selectedEntity = [pscustomobject]@{ DisplayName = 'stale' }
            $selectedEntityIndex = 3

            $result = Restore-XdrLiveEntitySelection -Context $context -EntitySelectionKey 'missing' -SelectedEntity ([ref]$selectedEntity) -SelectedEntityIndex ([ref]$selectedEntityIndex)

            $result | Should -BeFalse
            $selectedEntity | Should -BeNullOrEmpty
            $selectedEntityIndex | Should -Be 0
            $context.Selection.Entity | Should -BeNullOrEmpty
        }
    }
}
