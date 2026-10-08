# agent-brain

**A shared memory for your AI agents. Stored locally on your PC.**

[Deutsch](README.md) · [Download](https://github.com/Cobas91/agent-brain/releases/latest) · [Installation](docs/installation.md) · [Clients](docs/clients.md) · [Troubleshooting](docs/troubleshooting.md)

agent-brain stores concise facts, decisions and procedures in PostgreSQL with pgvector. Agents retrieve and maintain knowledge through MCP. Ollama creates embeddings locally. The dashboard lets you inspect content, sources, revisions and semantic relationships.

![Dashboard containing fictional demo knowledge only](docs/images/dashboard.jpg)

## Quick start on Windows

1. [**Download agent-brain.zip**](https://github.com/Cobas91/agent-brain/releases/latest/download/agent-brain.zip) and extract the **entire folder** to a permanent location, such as `D:\Tools\agent-brain`. Alternatively, use **Code → Download ZIP** or `git clone https://github.com/Cobas91/agent-brain.git`.
2. Double-click **`Setup-agent-brain.cmd`**. If Docker Desktop is missing, enable **“Docker Desktop installieren”**. Complete any Docker/WSL setup requested, then reopen the installer.
3. Select detected clients and click **“Jetzt ausführen”** (run now). Restart those clients when finished. Cursor and Claude Desktop require a manual instruction step described in the installer.
4. Open the [**dashboard**](http://127.0.0.1:8766). Ask a connected agent: “Search the Brain for existing knowledge. Remember for project demo: documentation is maintained in Markdown.” Check the saved entry in the dashboard.

Requirements: a [Docker Desktop supported Windows version](https://docs.docker.com/desktop/setup/install/windows-install/), 64-bit, PowerShell 5.1 or 7, local Linux containers and Docker Compose 2.20+. Plan for at least 8 GB RAM and several GB of free Docker storage. No GPU is needed. Initial installation downloads images, dependencies and the embedding model. The installer and dashboard currently use German labels.

You do not enter a password. The installer generates an internal database password in a protected local `.env`. **Keep this file and do not share it.** Repeated runs retain knowledge, model data, settings and unrelated client instructions.

## Features

- Shared global and project knowledge via seven MCP tools, with concise agent instructions.
- Local `embeddinggemma` embeddings with 768 dimensions; no cloud embedding API.
- Default retrieval: up to 5 results and 6000 text characters, plus metadata.
- Sources, revision checks, history, deduplication, archival and restore.
- Read-only dashboard with search, filters and a semantic map.
- Repeatable Windows installer with bounded retries, progress, diagnostics and recovery advice.

The [managed instructions](BRAIN-INSTRUCTIONS.md) ask agents to search first and maintain useful knowledge. Agents must actually call the tools; conversation monitoring is not built in. MCP uses Streamable HTTP at `http://127.0.0.1:8765/mcp`.

## Knowledge map

![Semantic map and example question using fictional demo knowledge](docs/images/knowledge-map.jpg)

Edges represent cosine similarity. A question highlights the entries that the same `brain_search` implementation would retrieve together with the selected parameters. Project searches include global knowledge. Spatial layout is approximate. This is a query preview, not a trace of another agent's tool calls. [Architecture and data model](docs/architecture.md).

## Installer and operations

![Rendered preview of the Windows WPF installer](docs/images/installer.png)

The installer image is a rendered preview of the actual WPF interface. Dashboard screenshots use only fictional records in a separate database. Installer scripts are UTF-8 with BOM to preserve German characters in Windows PowerShell 5.1.

```powershell
cd D:\Tools\agent-brain
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-AgentBrain.ps1
.\Install-AgentBrain.ps1 -Action Diagnose
.\Install-AgentBrain.ps1 -Action Configure -Agents Codex,ClaudeCode
.\Install-AgentBrain.ps1 -Action Backup
.\Install-AgentBrain.ps1 -Action Test
```

MCP and the dashboard bind to loopback only. PostgreSQL and Ollama expose no host ports. There is no application login; project scopes are retrieval filters rather than access boundaries. Knowledge retrieved by a cloud agent becomes part of its model context. Cloud-only MCP clients cannot directly reach localhost on your PC.

The guided installer supports Windows. The services are Linux containers; installation on other operating systems has not been validated. Never use `docker compose down -v` for routine maintenance: it deletes knowledge and models.

- [Installation and automation options](docs/installation.md)
- [Supported clients and manual MCP connections](docs/clients.md)
- [Troubleshooting, updates and backups](docs/troubleshooting.md)
- [Validation and limitations](TEST-REPORT.md)
- [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [MIT license](LICENSE)

agent-brain is an independent project. Its license does not replace the terms of embedding models, AI clients or Docker Desktop.
