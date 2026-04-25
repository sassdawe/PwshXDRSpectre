# PwshXDRSpectre

Terminal UI for Microsoft Defender XDR built with `PwshSpectreConsole`.

## Phase 1 architecture

The project now uses a module-first structure and shared runtime context:

- `PwshXDRSpectre.psm1`: module loader and public function exports.
- `Public/`: entry points and service functions.
- `Private/`: runtime context, operation wrappers, view-model converters, and helpers.
- `Tests/`: Pester tests for foundational contracts and wrapper wiring.

Current dashboard wrappers:

`Start-PwshXdrLiveDashboard`

Live dashboard mode uses:

1. Session connection flow.
2. Incident and alert retrieval services.
3. Runtime context model.
4. Structured operation/error envelopes.

## Prerequisites

### Entra ID app registration

Delegated permissions are recommended, so no certificate or client secret is required.

![delegated MSGraph permissions](./images/pwshxdr-delegated-api.png)

Any action performed with delegated permissions will be associated with your user identity in audit logs.

### Required modules

```powershell
#Requires -Version 7 -Modules PwshSpectreConsole, Microsoft.Graph.Authentication, Microsoft.Graph.Security
```

## Usage

### Live dashboard

```powershell
Import-Module ./src/PwshXDRSpectre.psm1;
Start-PwshXdrLiveDashboard -TenantId '867b6ce7-bde1-4b57-ad45-26c49b675e6c' -ClientId '7580ada2-de37-4ed3-8222-d4743cba052e'
```

Optional authentication mode:

```powershell
Import-Module ./src/PwshXDRSpectre.psm1;
Start-PwshXdrLiveDashboard -TenantId '<tenant-guid>' -ClientId '<app-client-id>' -UseDeviceCode
```

Example UI:

![PwshXDRSpectre in usage](./images/PwshXDR-usage.png)

## Tests

Run baseline Phase 1 tests:

```powershell
Invoke-Pester -Path ./src/Tests -Output Detailed
```

## Inspired by

https://github.com/ShaunLawrie/PwshEc2Tools
