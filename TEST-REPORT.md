# Validation and known limits

Validated locally on Windows on **2026-10-09**. This is a record of observed checks, not a guarantee for every Windows configuration. See [CONTRIBUTING.md](CONTRIBUTING.md) for commands.

## Installer

- **68 assertions pass** on Windows PowerShell 5.1.26100.9444 and PowerShell 7.6.5, run sequentially.
- Tests use isolated temporary fixtures. Prerequisite-error cases simulate Docker/winget and never install software or modify real client configurations.
- Source parsing and UTF-8 BOM checks pass. Real child-process output preserves `Größe ändern – für alle`; Unicode JSON settings survive repeated configuration.
- Repeated settings/instructions are byte-identical, retain unrelated content and add no backup when unchanged. Malformed files/markers, concurrent edits, per-client rollback and partial client failure are covered.
- Fresh `.env`, password retention, dashboard-port upgrades, duplicate/invalid settings and lost `.env` with an existing data volume are covered.
- Real process checks cover exit codes, quoted arguments, paths with spaces/Unicode, shell metacharacters, bounded timeouts and tree termination.
- Retry classification, occupied ports, remote Docker/context precedence, Windows containers, old Compose, reboot signals and offline Stop/Status are covered.
- Real entry-point failures produce recommendations/reports; concurrent installer processes are blocked.
- Previous live startup and repeated unchanged starts preserved knowledge/volumes and skipped rebuilds/model downloads. PowerShell 5.1/7 fingerprints matched. Real database backup passed archive validation.
- WPF construction, five client choices and worker argument transport pass. The actual hidden GUI worker ran read-only Diagnose and produced successful progress/completion JSON. The installer image is an offscreen render of the actual WPF interface.

## Services and knowledge

- Live PostgreSQL, MCP and dashboard health checks pass; real Ollama produces 768-dimensional embeddings.
- MCP HTTP and stdio integration tests cover all seven tools, default context limits, project filtering, exact deduplication, revision conflicts, credential rejection, archive, history and restore.
- Nine policy unit tests pass.
- Dashboard tests cover pagination, scope/type/status filters, literal search, sources/history, invalid inputs, read-only routes, Host checks and content-security policy.
- Map tests compare real PostgreSQL cosine scores, exclude archived rows, enforce node limits and prioritized question hits, and reject invalid inputs. Question preview matches the MCP search implementation and respects its text budget.
- Browser checks covered library details/history, empty states, map query hits/ranks, node inspection, navigation, zoom and a 390px responsive layout without horizontal overflow.
- Public dashboard screenshots show only fictional records from a separate temporary database; actual knowledge is not included in the repository or release.

## Boundaries

- Fresh Windows Docker/WSL installation and reboot handling were simulated, not tested on a clean machine. BIOS/WSL changes and forced reboots are not performed.
- Interactive WPF window actions have not all been manually acceptance-tested. Headless rendering and the actual background worker were tested.
- Codex's connected MCP tools were exercised live. Gemini/Cursor formats were checked against documentation; every supported client's full application interaction has not been tested.
- CI runs isolated policy/installer tests; full Docker/model integration is a separate local check. Linux/macOS installer workflows are not validated.
- MCP SDK may emit a Pydantic lifespan annotation warning; tested runtime paths work.
- Instructions cannot enforce tool usage or optimal wording. Secret detection/log redaction are heuristic; map layout distances are approximate.
