I’ll map your workflow rules to a simple tagging flow and give copy/paste-safe commands for first release, re-tagging mistakes, and manual dispatch fallback.Use tags as release markers in Git. Your workflow in release-github-artifact.yml runs automatically when a pushed tag matches v*.

Important rules from your workflow:
1. Tag must start with v
2. Tag version must equal ModuleVersion in PwshXDRSpectre.psd1

Practical flow

1. Update module version first
- Edit ModuleVersion in PwshXDRSpectre.psd1, for example 0.1.1
- Commit and push that change to main

2. Create a matching tag locally
- git tag -a v0.1.1 -m "Release v0.1.1"

3. Push the tag to GitHub (this triggers the pipeline)
- git push origin v0.1.1

That is all you need for automatic trigger.

If you tagged the wrong version

1. Delete local tag
- git tag -d v0.1.1

2. Delete remote tag
- git push origin :refs/tags/v0.1.1

3. Create and push the corrected tag
- git tag -a v0.1.2 -m "Release v0.1.2"
- git push origin v0.1.2

Manual alternative (no tag push yet)

You can run the same workflow from Actions using workflow_dispatch and provide:
1. tag: vX.Y.Z
2. prerelease: true or false

But it still validates that tag version matches the manifest version, so keep those aligned.

Quick habit that avoids failures

Before tagging, confirm:
1. ModuleVersion in PwshXDRSpectre.psd1 is the intended release version
2. You create tag as v plus that exact version
3. You push the tag, not just the commit

If you want, I can also give you a tiny release checklist you can paste into your README so this becomes a repeatable process.