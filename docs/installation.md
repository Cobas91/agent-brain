# Installation and operations

[Deutsch: Schnellstart](../README.md#in-wenigen-schritten-starten) · [English quick start](../README.en.md#quick-start-on-windows)

## Prepare your PC

Use 64-bit Windows supported by [Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/), Windows PowerShell 5.1 or PowerShell 7, and a **local Linux Docker engine** with Compose 2.20+. Docker's current Windows requirements apply, including virtualization and its chosen backend. Plan for at least 8 GB RAM and several GB of Docker storage; no GPU is required. Docker Desktop has its own licensing terms.

The installer can install missing Docker Desktop through winget when explicitly selected. It does not change BIOS settings, force a reboot or automatically repair WSL. Complete any Windows/Docker setup requested and run the installer again. Normal operations do not require an elevated shell; Docker/Windows prerequisites may.

## Download and start

Download [agent-brain.zip](https://github.com/Cobas91/agent-brain/releases/latest/download/agent-brain.zip) and extract the entire package to a permanent local folder with write permission. Do not run inside the ZIP. `Setup-agent-brain.cmd` launches the graphical installer. Select clients, optionally enable Docker installation, and click **Jetzt ausführen**.

The package must include `installer/`, `server/`, `compose.yaml`, `BRAIN-INSTRUCTIONS.md` and the entry-point scripts. Moving the folder later requires reconfiguring Claude Desktop's absolute paths. Neither Git nor host Python/Ollama is needed to use the downloaded package; Python and Ollama run in Docker. Internet is needed on the first run.

For the console installer:

```powershell
cd D:\Tools\agent-brain
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-AgentBrain.ps1
# Install missing Docker Desktop explicitly:
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-AgentBrain.ps1 -InstallDocker
```

The launcher applies execution-policy bypass only to its own process. Existing organization restrictions may still prevent execution. The console waits for a key after success or failure; the graphical window remains open. A nonzero exit code indicates failure.

## Actions

| Action | Purpose |
|---|---|
| `Install` (default) | Prepare prerequisites/settings, build/start the stack, configure selected clients. |
| `Start` | Start or resume the stack; configure clients unless skipped. |
| `Configure` | Configure selected clients and managed instructions. |
| `Diagnose` | Inspect prerequisites, existing services and endpoints; no service start or client changes. |
| `Status` | Show existing stack status. |
| `Test` | Run real MCP/Ollama/PostgreSQL/dashboard integration checks. |
| `Backup` | Create a validated PostgreSQL dump in `backups/database/`. |
| `Stop` | Stop services without deleting their data. |

`Status`, `Stop`, `Backup` and `Test` do not start an offline Docker engine. Diagnostics may write a local report. `Stop` treats an already offline local engine as stopped.

```powershell
.\Install-AgentBrain.ps1 -Action Start -SkipAgentSetup -NonInteractive -NoPause
.\Install-AgentBrain.ps1 -Action Configure -Agents Codex,ClaudeCode -NonInteractive -NoPause
.\Install-AgentBrain.ps1 -Action Diagnose -NoPause
.\Install-AgentBrain.ps1 -DetectionOnly
```

`-NonInteractive` disables selection and the closing prompt. Without `-Agents`, it skips automatic client setup. `-NoPause` only disables the closing prompt. `-DetectionOnly` lists detected clients without changes. Detection uses CLI availability, installation locations and existing configuration; leftover configuration can therefore appear as a detected client.

## Repeatability and recovery

Existing `.env`, database/model volumes and unrelated client settings are retained. Matching client configuration and instructions are not rewritten or backed up again. The managed instruction block stays unique. Changed configuration is backed up first; a failed client's changes are rolled back where possible. Files edited concurrently are preserved. Other selected clients continue after one fails, but the overall result reports failure.

A healthy, unchanged stack skips rebuilds and model downloads. Package/configuration fingerprints are consistent across PowerShell 5.1 and 7. If startup was interrupted, rerun the same action; completed Docker resources are reused. The installer retries transient network failures and rejects invalid settings/occupied ports with recommendations. It never kills unrelated port owners.

An existing database volume with a missing `.env` stops setup: restore the original file instead of generating a new password. A user-scoped lock prevents concurrent installer runs. **Folder copies share the fixed `agent-brain` stack and volumes; they are not independent installations.**

## Ports, time limits and local files

Defaults: MCP `8765`, dashboard `8766`. On first setup use `-Port` and `-DashboardPort`; afterward `.env` is authoritative. Stop services before changing saved ports, restart them and reconfigure clients. A conflicting existing Codex/Claude Code registration needs manual correction before retrying. Ports must be distinct and between 1024 and 65535.

```powershell
# For slower downloads or Docker startup:
.\Install-AgentBrain.ps1 -TimeoutSeconds 1800 -DockerWaitSeconds 300 -Retries 3
```

Defaults: normal external command 120 seconds, Docker startup 180 seconds, build/download/test 900 seconds and three attempts for transient failures. Error reports include the failed step, code and suggested next actions.

| Local path | Contents |
|---|---|
| `.env` | Generated internal database password and saved ports; retain privately. |
| `installer-state.json` | Last successful stack fingerprint. |
| `logs/<run-id>.log` and `.json` | Redacted progress and structured completion report. |
| `backups/client-config/` | Original changed client configuration/instruction files. |
| `backups/database/` | Database dump archives. |

Private files are restricted to the current Windows user and SYSTEM. Redaction is heuristic; review logs before sharing. Config backups may contain credentials from other services. All these runtime paths are excluded from Git and release packages.

## Updating

Make a database backup and retain `.env`. With Git, update a clean checkout using `git pull --ff-only`, then rerun the installer. With ZIP releases, replace source files in the existing permanent folder while retaining `.env`, backups, logs and installer state. The installer rebuilds changed server files and keeps existing volumes. Do not create a second independent-looking installation directory or use `down -v`.

Breaking database/model migrations require explicit release instructions. Changing the embedding model without re-embedding is rejected. [Troubleshooting and recovery](troubleshooting.md).
