# Publishing a release

End users download `agent-brain.zip` from a **GitHub Release**, then extract the complete folder. ZIP archives are ignored by Git and are never committed.

Maintainers should run local regression/integration checks, verify GitHub CI, update both READMEs as needed and commit the release source. Build from that commit or tag:

```powershell
.\scripts\New-ReleasePackage.ps1 -Ref HEAD
```

The script uses `git archive`, includes only tracked files under `agent-brain/`, and refuses tracked private/runtime paths or nested archives. It prints the exact commit and SHA-256. Git is needed for building a release, not for installing the downloaded package. Use `-Force` only to replace an earlier generated archive.

Write release notes to a UTF-8 file outside the tracked source, then publish with GitHub CLI:

```powershell
# Replace VERSION with the actual release version, e.g. v0.1.0.
gh release create VERSION .\dist\agent-brain.zip --target main --title "agent-brain VERSION" --notes-file <release-notes-file>
```

Verify the published release asset and download it once. Its SHA-256 must match the generated package. The READMEs use GitHub's latest-release asset URL, so future releases must keep the asset name **agent-brain.zip**.

Retain `.env` when upgrading; data/model volumes are reused. Document any breaking migrations explicitly before publishing.
