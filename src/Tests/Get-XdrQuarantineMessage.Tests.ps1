BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrQuarantineMessage' {
    It 'returns normalized quarantine message view models with the requested limit' {
        InModuleScope PwshXDRSpectre {
            function Get-QuarantineMessage {
                param(
                    [string]$RecipientAddress
                )

                $RecipientAddress | Should -Be 'recipient@example.com'
                @(
                    [pscustomobject]@{ Identity = 'msg-1'; Subject = 'First'; RecipientAddress = $RecipientAddress },
                    [pscustomobject]@{ Identity = 'msg-2'; Subject = 'Second'; RecipientAddress = $RecipientAddress }
                )
            }

            $result = Get-XdrQuarantineMessage -RecipientAddress 'recipient@example.com' -Limit 1

            $result | Should -HaveCount 1
            $result[0].Identity | Should -Be 'msg-1'
            $result[0].Subject | Should -Be 'First'

            Remove-Item -Path Function:\Get-QuarantineMessage -ErrorAction SilentlyContinue
        }
    }

    It 'throws a clear error when Exchange quarantine cmdlets are unavailable' {
        InModuleScope PwshXDRSpectre {
            Remove-Item -Path Function:\Get-QuarantineMessage -ErrorAction SilentlyContinue

            { Get-XdrQuarantineMessage } | Should -Throw '*Connect-ExchangeOnline*'
        }
    }

    Context 'comment-based help' {
        It 'has a Synopsis' {
            (Get-Help Get-XdrQuarantineMessage).Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'has a Description' {
            (Get-Help Get-XdrQuarantineMessage).Description | Should -Not -BeNullOrEmpty
        }
    }
}
