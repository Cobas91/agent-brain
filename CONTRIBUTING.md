# Contributing

Issues and pull requests are welcome. Describe the problem, expected behavior, affected client/version and a minimal reproduction. Share synthetic data only. See [SECURITY.md](SECURITY.md) for vulnerabilities.

## Layout

```text
Install-AgentBrain.ps1       Windows entry point
Setup-agent-brain.cmd        GUI launcher
installer/                  Core operations, client setup, WPF interface
compose.yaml                Local Docker stack
server/                     MCP, persistence, dashboard and integration tests
tests/                      Isolated installer/policy regression tests
docs/                       Guides and public demo screenshots
.github/workflows/          Automated regression checks
```

Edit PowerShell sources as **UTF-8 with BOM**; Windows PowerShell 5.1 needs the BOM for non-ASCII source. Keep native argument transport, redaction, timeouts, revision checks and non-destructive recovery intact. Do not add remote assets or tracking to the dashboard.

## Checks

On Windows, run these sequentially; entry-point cases share the real installer lock:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Installer.ps1
pwsh -NoProfile -File tests\Test-Installer.ps1
```

These tests use isolated temporary fixtures; they do not configure your actual clients or install Docker. The policy tests need Python 3.12 and pytest:

```text
python -m pip install pytest==8.4.2
python -m pytest tests/test_policy.py -q
```

For changes to MCP, schema, embeddings or dashboard, also start the local stack and run:

```powershell
.\Install-AgentBrain.ps1 -Action Test -NonInteractive -NoPause
```

This uses real PostgreSQL/Ollama/MCP and disposable randomized test scopes. CI runs policy checks and both PowerShell versions; full Docker/model integration remains a separate local check. GUI preview checks can run headlessly on Windows:

```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File installer\Gui.ps1 -SmokeTest -PreviewPath "$env:TEMP\agent-brain-installer.png"
```

Add `-WorkerCheck` only with a running installation to verify the hidden Diagnose worker. Inspect UI changes visually as well.

Dependency changes must update `server/requirements.txt` and the complete `requirements.lock`, then pass a Docker build and real integration tests. The lock pins transitive versions but not artifact hashes. PostgreSQL/model upgrades need a documented backup/migration plan; do not silently mix embedding spaces.

Keep both READMEs consistent. Screenshots must contain fictional data only and no user-specific source paths. [Release archives](docs/releases.md) are built from tracked Git files using `git archive`, excluding `.env`, logs, backups and local state. Upload ZIPs as GitHub Release assets; never commit them.
