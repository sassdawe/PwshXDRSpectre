# Secure SDLC Policy

## Purpose
This policy defines the minimum security controls for planning, coding, validating, releasing, and operating PwshXDRSpectre.

## Scope
Applies to all source code, workflows, release artifacts, dependencies, and contributor pull requests in this repository.

## Security Gates
The following are mandatory before merge to `main`:

1. CI quality checks pass (manifest validation, linting, tests).
2. Dependency review passes on pull requests.
3. Code scanning workflow is enabled and producing no unresolved high-risk findings for modified code.
4. No secrets are committed (automated secret scanning in CI).

## Development Requirements
1. All changes must be submitted through pull requests.
2. At least one reviewer approval is required.
3. Changes to workflows, security policy, or release automation require security-aware review.
4. New third-party dependencies must be justified and reviewed.
5. Actions in workflows must be pinned to immutable commit SHAs.

## Threat Modeling and Risk Handling
1. Security-impacting features should include brief abuse-case notes in PR description.
2. High-risk findings must be remediated before merge.
3. Medium findings require a tracked follow-up issue when not fixed in the same PR.
4. Risk acceptance requires explicit maintainer sign-off in PR comments.

## Release Security Requirements
1. Release tag version must match `ModuleVersion` in `src/PwshXDRSpectre.psd1`.
2. Required assets (for example `src/ANSI Shadow.flf`) must be verified in packaged artifacts.
3. Only automated release workflows publish artifacts and PowerShell Gallery releases.

## Secrets and Credentials
1. Secrets are stored only in GitHub Actions encrypted secrets.
2. Secrets must never be committed or logged.
3. Production tokens must have least privilege and rotation ownership.

## Incident Response
1. Security reports are handled according to `SECURITY.md`.
2. Confirmed vulnerabilities should be triaged within 3 business days.
3. Fix timelines:
   - Critical: 48 hours target
   - High: 7 days target
   - Medium: 30 days target

## Compliance and Exceptions
1. Policy exceptions must be documented in PR with rationale and expiry date.
2. Maintainers review this policy quarterly and after major incidents.
