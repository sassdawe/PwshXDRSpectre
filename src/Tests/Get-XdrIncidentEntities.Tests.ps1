BeforeAll {
    Import-Module "$PSScriptRoot/../PwshXDRSpectre.psm1" -Force
}

Describe 'Get-XdrIncidentEntities' {
    It 'extracts assigned user and alert entities' {
        InModuleScope PwshXDRSpectre {
            $incident = [pscustomobject]@{
                IncidentId = 'inc-1'
                AssignedTo = 'analyst@contoso.com'
            }

            $alerts = @(
                [pscustomobject]@{
                    AlertId = 'alert-1'
                    Title = 'Suspicious sign-in'
                    RawObject = $null
                }
            )

            $result = @(Get-XdrIncidentEntities -Incident $incident -Alerts $alerts)

            $result.Count | Should -BeGreaterThan 1
            (@($result | Where-Object { $_.EntityType -eq 'User' }).Count) | Should -Be 1
            (@($result | Where-Object { $_.EntityType -eq 'Alert' }).Count) | Should -Be 1
        }
    }

    It 'deduplicates identical entities' {
        InModuleScope PwshXDRSpectre {
            $incident = [pscustomobject]@{
                IncidentId = 'inc-2'
                AssignedTo = 'analyst@contoso.com'
            }

            $alerts = @(
                [pscustomobject]@{ AlertId = 'a-1'; Title = 'Suspicious sign-in'; RawObject = $null },
                [pscustomobject]@{ AlertId = 'a-2'; Title = 'Suspicious sign-in'; RawObject = $null }
            )

            $result = @(Get-XdrIncidentEntities -Incident $incident -Alerts $alerts)
            $alertEntities = @($result | Where-Object { $_.EntityType -eq 'Alert' -and $_.DisplayName -eq 'Suspicious sign-in' })

            $alertEntities.Count | Should -Be 1
        }
    }

    It 'extracts entities from alert evidence and raw alert evidence' {
        InModuleScope PwshXDRSpectre {
            $incident = [pscustomobject]@{
                IncidentId = 'inc-3'
                AssignedTo = ''
            }

            $alerts = @(
                [pscustomobject]@{
                    AlertId = 'a-3'
                    Title = 'Mixed evidence'
                    Evidence = @(
                        [pscustomobject]@{ EntityType = 'Device'; DeviceName = 'device-01' }
                    )
                    RawObject = [pscustomobject]@{
                        Evidence = @(
                            [pscustomobject]@{ EntityType = 'File'; FileName = 'evil.bin' }
                        )
                    }
                }
            )

            $result = @(Get-XdrIncidentEntities -Incident $incident -Alerts $alerts)

            (@($result | Where-Object { $_.EntityType -eq 'Device' -and $_.DisplayName -eq 'device-01' }).Count) | Should -Be 1
            (@($result | Where-Object { $_.EntityType -eq 'File' -and $_.DisplayName -eq 'evil.bin' }).Count) | Should -Be 1
        }
    }

    It 'deduplicates entities repeated between alert and raw evidence' {
        InModuleScope PwshXDRSpectre {
            $incident = [pscustomobject]@{
                IncidentId = 'inc-4'
                AssignedTo = ''
            }

            $sharedEntity = [pscustomobject]@{ EntityType = 'Device'; DeviceName = 'device-dup' }
            $alerts = @(
                [pscustomobject]@{
                    AlertId = 'a-4'
                    Title = 'Duplicate evidence'
                    Evidence = @($sharedEntity)
                    RawObject = [pscustomobject]@{
                        Evidence = @($sharedEntity)
                    }
                }
            )

            $result = @(Get-XdrIncidentEntities -Incident $incident -Alerts $alerts)
            $matches = @($result | Where-Object { $_.EntityType -eq 'Device' -and $_.DisplayName -eq 'device-dup' })

            $matches.Count | Should -Be 1
        }
    }

    It 'extracts entities from alert entities collection when raw object is absent' {
        InModuleScope PwshXDRSpectre {
            $incident = [pscustomobject]@{
                IncidentId = 'inc-5'
                AssignedTo = ''
            }

            $alerts = @(
                [pscustomobject]@{
                    AlertId = 'a-5'
                    Title = 'Entities collection'
                    Entities = @(
                        [pscustomobject]@{ EntityType = 'User'; UserPrincipalName = 'user1@contoso.com' },
                        [pscustomobject]@{ EntityType = 'Url'; Url = 'https://contoso.test/path' }
                    )
                }
            )

            $result = @(Get-XdrIncidentEntities -Incident $incident -Alerts $alerts)

            (@($result | Where-Object { $_.EntityType -eq 'User' -and $_.DisplayName -eq 'user1@contoso.com' }).Count) | Should -Be 1
            (@($result | Where-Object { $_.EntityType -eq 'Url' -and $_.DisplayName -eq 'https://contoso.test/path' }).Count) | Should -Be 1
        }
    }

    It 'extracts IP and URL evidence values' {
        InModuleScope PwshXDRSpectre {
            $incident = [pscustomobject]@{
                IncidentId = 'inc-6'
                AssignedTo = ''
            }

            $alerts = @(
                [pscustomobject]@{
                    AlertId = 'a-6'
                    Title = 'Network indicators'
                    Evidence = @(
                        [pscustomobject]@{ IpAddress = '10.20.30.40' },
                        [pscustomobject]@{ Url = 'https://example.org/signal' }
                    )
                }
            )

            $result = @(Get-XdrIncidentEntities -Incident $incident -Alerts $alerts)

            (@($result | Where-Object { $_.EntityType -eq 'IpAddress' -and $_.DisplayName -eq '10.20.30.40' }).Count) | Should -Be 1
            (@($result | Where-Object { $_.EntityType -eq 'Url' -and $_.DisplayName -eq 'https://example.org/signal' }).Count) | Should -Be 1
        }
    }

    It 'uses Type when EntityType is missing' {
        InModuleScope PwshXDRSpectre {
            $incident = [pscustomobject]@{
                IncidentId = 'inc-7'
                AssignedTo = ''
            }

            $alerts = @(
                [pscustomobject]@{
                    AlertId = 'a-7'
                    Title = 'Type fallback'
                    Evidence = @(
                        [pscustomobject]@{ Type = 'Device'; DeviceName = 'host-fallback' }
                    )
                }
            )

            $result = @(Get-XdrIncidentEntities -Incident $incident -Alerts $alerts)
            $match = @($result | Where-Object { $_.EntityType -eq 'Device' -and $_.DisplayName -eq 'host-fallback' })

            $match.Count | Should -Be 1
        }
    }

    It 'extracts user from Graph AdditionalProperties userEvidence payload' {
        InModuleScope PwshXDRSpectre {
            $incident = [pscustomobject]@{ IncidentId = 'inc-8'; AssignedTo = '' }
            $alerts = @(
                [pscustomobject]@{
                    AlertId = 'a-8'
                    Title = 'Graph user evidence'
                    Evidence = @(
                        [pscustomobject]@{
                            AdditionalProperties = @{
                                '@odata.type' = '#microsoft.graph.security.userEvidence'
                                userAccount = @{
                                    userPrincipalName = 'graph.user@contoso.com'
                                    azureAdUserId = '11111111-2222-3333-4444-555555555555'
                                }
                            }
                        }
                    )
                }
            )

            $result = @(Get-XdrIncidentEntities -Incident $incident -Alerts $alerts)
            $match = @($result | Where-Object { $_.EntityType -eq 'User' -and $_.DisplayName -eq 'graph.user@contoso.com' })

            $match.Count | Should -Be 1
            $match[0].UserId | Should -Be '11111111-2222-3333-4444-555555555555'
            $match[0].UserPrincipalName | Should -Be 'graph.user@contoso.com'
        }
    }

    It 'extracts device and file from Graph AdditionalProperties payloads' {
        InModuleScope PwshXDRSpectre {
            $incident = [pscustomobject]@{ IncidentId = 'inc-9'; AssignedTo = '' }
            $alerts = @(
                [pscustomobject]@{
                    AlertId = 'a-9'
                    Title = 'Graph device and file evidence'
                    Evidence = @(
                        [pscustomobject]@{
                            AdditionalProperties = @{
                                '@odata.type' = '#microsoft.graph.security.deviceEvidence'
                                deviceDnsName = 'host-graph.contoso.com'
                                mdeDeviceId = 'mde-device-123'
                            }
                        },
                        [pscustomobject]@{
                            AdditionalProperties = @{
                                '@odata.type' = '#microsoft.graph.security.fileEvidence'
                                fileDetails = @{
                                    sha256 = 'abc123'
                                    fileName = 'payload.exe'
                                }
                            }
                        }
                    )
                }
            )

            $result = @(Get-XdrIncidentEntities -Incident $incident -Alerts $alerts)
            $deviceMatch = @($result | Where-Object { $_.EntityType -eq 'Device' -and $_.DisplayName -eq 'host-graph.contoso.com' })
            $fileMatch = @($result | Where-Object { $_.EntityType -eq 'File' -and $_.DisplayName -eq 'abc123' })

            $deviceMatch.Count | Should -Be 1
            $deviceMatch[0].DeviceId | Should -Be 'mde-device-123'
            $fileMatch.Count | Should -Be 1
            $fileMatch[0].Sha256 | Should -Be 'abc123'
        }
    }

    It 'extracts IP URL and analyzed message URLs from Graph AdditionalProperties payloads' {
        InModuleScope PwshXDRSpectre {
            $incident = [pscustomobject]@{ IncidentId = 'inc-10'; AssignedTo = '' }
            $alerts = @(
                [pscustomobject]@{
                    AlertId = 'a-10'
                    Title = 'Graph network evidence'
                    Evidence = @(
                        [pscustomobject]@{
                            AdditionalProperties = @{
                                '@odata.type' = '#microsoft.graph.security.ipEvidence'
                                ipAddress = '203.0.113.10'
                            }
                        },
                        [pscustomobject]@{
                            AdditionalProperties = @{
                                '@odata.type' = '#microsoft.graph.security.urlEvidence'
                                url = 'https://graph-url.contoso/path'
                            }
                        },
                        [pscustomobject]@{
                            AdditionalProperties = @{
                                '@odata.type' = '#microsoft.graph.security.analyzedMessageEvidence'
                                urls = @('https://mail-url-1.contoso', 'https://mail-url-2.contoso')
                            }
                        }
                    )
                }
            )

            $result = @(Get-XdrIncidentEntities -Incident $incident -Alerts $alerts)
            (@($result | Where-Object { $_.EntityType -eq 'IpAddress' -and $_.DisplayName -eq '203.0.113.10' }).Count) | Should -Be 1
            (@($result | Where-Object { $_.EntityType -eq 'Url' -and $_.DisplayName -eq 'https://graph-url.contoso/path' }).Count) | Should -Be 1
            (@($result | Where-Object { $_.EntityType -eq 'Url' -and $_.DisplayName -eq 'https://mail-url-1.contoso' }).Count) | Should -Be 1
            (@($result | Where-Object { $_.EntityType -eq 'Url' -and $_.DisplayName -eq 'https://mail-url-2.contoso' }).Count) | Should -Be 1
        }
    }
}
