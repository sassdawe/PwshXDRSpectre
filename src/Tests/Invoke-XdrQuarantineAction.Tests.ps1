BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Invoke-XdrQuarantineAction' {
    It 'releases a quarantined message to all original recipients' {
        InModuleScope PwshXDRSpectre {
            $script:lastReleaseParameters = $null
            function Release-QuarantineMessage {
                param(
                    [string]$Identity,
                    [bool]$ReleaseToAll,
                    [string[]]$RecipientAddress
                )

                $script:lastReleaseParameters = [pscustomobject]@{
                    Identity         = $Identity
                    ReleaseToAll     = $ReleaseToAll
                    RecipientAddress = $RecipientAddress
                }

                [pscustomobject]@{ Status = 'Released' }
            }

            $result = Invoke-XdrQuarantineAction -Identity 'msg-1' -Action Release -ReleaseToAll -PassThru -Confirm:$false

            $result.Status | Should -Be 'Released'
            $script:lastReleaseParameters.Identity | Should -Be 'msg-1'
            $script:lastReleaseParameters.ReleaseToAll | Should -BeTrue

            Remove-Item -Path Function:\Release-QuarantineMessage -ErrorAction SilentlyContinue
        }
    }

    It 'requires an explicit release target before calling Exchange Online' {
        InModuleScope PwshXDRSpectre {
            function Release-QuarantineMessage {
                throw 'Release should not be called without a target.'
            }

            { Invoke-XdrQuarantineAction -Identity 'msg-1' -Action Release -Confirm:$false } | Should -Throw '*ReleaseToAll*'

            Remove-Item -Path Function:\Release-QuarantineMessage -ErrorAction SilentlyContinue
        }
    }

    It 'deletes a quarantined message through Exchange Online' {
        InModuleScope PwshXDRSpectre {
            $script:lastDeletedIdentity = $null
            function Delete-QuarantineMessage {
                param(
                    [string]$Identity
                )

                $script:lastDeletedIdentity = $Identity
                [pscustomobject]@{ Status = 'Deleted' }
            }

            $result = Invoke-XdrQuarantineAction -Identity 'msg-2' -Action Delete -PassThru -Confirm:$false

            $result.Status | Should -Be 'Deleted'
            $script:lastDeletedIdentity | Should -Be 'msg-2'

            Remove-Item -Path Function:\Delete-QuarantineMessage -ErrorAction SilentlyContinue
        }
    }

    Context 'comment-based help' {
        It 'has a Synopsis' {
            (Get-Help Invoke-XdrQuarantineAction).Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'has a Description' {
            (Get-Help Invoke-XdrQuarantineAction).Description | Should -Not -BeNullOrEmpty
        }
    }
}
