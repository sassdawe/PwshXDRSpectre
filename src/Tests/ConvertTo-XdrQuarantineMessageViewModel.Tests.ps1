BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'ConvertTo-XdrQuarantineMessageViewModel' {
    It 'maps common Exchange quarantine message fields' {
        InModuleScope PwshXDRSpectre {
            $message = [pscustomobject]@{
                Identity            = 'msg-1'
                QuarantineMessageId = 'internet-msg-1'
                SenderAddress       = 'sender@example.com'
                RecipientAddress    = 'recipient@example.com'
                Subject             = 'Suspicious message'
                QuarantineType      = 'Phish'
                ReleaseStatus       = 'NotReleased'
                ReceivedTime        = [datetime]'2026-05-20T10:00:00Z'
                Expires             = [datetime]'2026-06-20T10:00:00Z'
            }

            $result = $message | ConvertTo-XdrQuarantineMessageViewModel

            $result.Identity | Should -Be 'msg-1'
            $result.SenderAddress | Should -Be 'sender@example.com'
            $result.RecipientAddress | Should -Be 'recipient@example.com'
            $result.Subject | Should -Be 'Suspicious message'
            $result.QuarantineType | Should -Be 'Phish'
            $result.ReleaseStatus | Should -Be 'NotReleased'
            $result.Raw | Should -Be $message
        }
    }
}
