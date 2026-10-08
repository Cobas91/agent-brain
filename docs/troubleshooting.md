# Troubleshooting, backups and recovery

Start with the installer's **Diagnose** action. It reports the affected step, an error code and next actions. Rerun after correcting the cause; do not reset volumes as a repair shortcut.

```powershell
.\Install-AgentBrain.ps1 -Action Diagnose
```

| Code / symptom | Next action |
|---|---|
| `DOCKER_MISSING` / `WINGET_MISSING` | Install Docker Desktop manually or select its installer option with winget available. |
| `DOCKER_ENGINE` | Open Docker Desktop and complete setup; use Linux containers. Check WSL/virtualization using the displayed advice. |
| `REBOOT_REQUIRED` | Restart Windows yourself, finish Docker setup and rerun the installer. |
| `REMOTE_DOCKER` | Select a local Docker context; inspect `DOCKER_CONTEXT` and `DOCKER_HOST` overrides. |
| `COMPOSE_VERSION` | Update Docker Desktop/Compose to at least 2.20. |
| `PORT_BUSY` | Choose free ports on first setup, or stop the conflicting app yourself. |
| `PORT_CONFIG` | Saved `.env` ports win. Stop the stack, change saved ports and reconfigure clients deliberately. |
| `ENV_LOST` with existing volume | Recover the original `.env` from the previous installation/private backup. Do not generate a replacement password or delete the volume. |
| `ENV_INVALID` | Check duplicate keys, password format and distinct ports 1024–65535. Do not share the file. |
| `CONFIG_INVALID` / `CONFIG_CHANGED` | Repair malformed client JSON/instruction markers or restore its private backup; close editors changing it concurrently. |
| `CLIENT_ENDPOINT` | Correct an existing conflicting registration manually, then rerun Configure. |
| `CLIENT_FAILED` | Inspect per-client results; retry the specific client. The Brain services may already work. |
| `INSTALL_BUSY` | Complete the other installer run. |
| `TIMEOUT` / `STACK_UNHEALTHY` | Diagnose first; check network/proxy, Docker storage and model initialization. Increase bounded time limits if needed. |
| `FILE_ACCESS` / `DISK_SPACE` | Use a writable local NTFS folder and free space on both its drive and Docker's storage drive. |
| Agent has no Brain tools | Restart it, check the registered endpoint and confirm the stack is running. |
| Empty search | This may mean no matching knowledge. Try another query or inspect the dashboard. |
| GUI does not open | Extract the whole package and run the console entry point to see the error. |

Logs are under `logs/`. Review/redact them before opening an issue: redaction is heuristic and private paths may appear. Do not attach `.env`, client configurations, database dumps or real knowledge.

## Back up

```powershell
.\Install-AgentBrain.ps1 -Action Backup
```

This creates a binary pg_dump archive, checks it with `pg_restore --list`, then finalizes it under `backups/database/`. Keep a private copy of `.env` separately; it is not included in a database dump. Client configuration backups are separate and can contain credentials for other services.

## Restore a database backup

**Restore deliberately replaces current database contents with the selected backup.** First create a fresh backup and retain `.env`. Pause agents writing to the Brain and stop both application services. Choose the actual dump file; do not paste the placeholder literally.

```powershell
cd D:\Tools\agent-brain
docker compose stop dashboard mcp
docker compose cp .\backups\database\<FILE>.dump postgres:/tmp/brain-restore.dump
docker compose exec -T postgres pg_restore -U agent_brain -d agent_brain --clean --if-exists --single-transaction /tmp/brain-restore.dump
# Continue only if pg_restore succeeded:
docker compose exec -T postgres rm /tmp/brain-restore.dump
docker compose start mcp dashboard
.\Install-AgentBrain.ps1 -Action Test
```

If restore fails, keep the applications stopped and inspect the error. The single transaction prevents a partly applied restore. For one mistaken knowledge edit, prefer `brain_history` and `brain_restore` rather than replacing the whole database.

## Stop and restart

`-Action Stop` preserves knowledge and models. Start Docker Desktop and run `-Action Start` to resume. The services use `restart: unless-stopped`, so an explicitly stopped container requires a subsequent start. Never use `docker compose down -v` for routine operations: it deletes the persistent volumes.
