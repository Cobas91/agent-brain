# Connecting your agents

Restart clients after configuration. The installer offers detected clients; explicit `-Agents` is useful for automation. All clients share the same knowledge database.

| Client | MCP connection | Managed instructions |
|---|---|---|
| Codex CLI / desktop using its shared configuration | Streamable HTTP through `codex mcp add` | `$CODEX_HOME/AGENTS.md`, otherwise `~/.codex/AGENTS.md`; existing `AGENTS.override.md` takes precedence and is used. |
| Claude Code | HTTP, user scope | `~/.claude/CLAUDE.md`; respects `CLAUDE_CONFIG_DIR`. |
| Gemini CLI | `httpUrl` in `~/.gemini/settings.json` | `~/.gemini/GEMINI.md` with default context configuration. |
| Cursor | `url` in `~/.cursor/mcp.json` | Manually paste [BRAIN-INSTRUCTIONS.md](../BRAIN-INSTRUCTIONS.md) into Settings → Rules → User Rules. |
| Claude Desktop | stdio through Docker Compose in its desktop JSON configuration | Manually paste the instructions into the applicable profile/project instructions. |

Codex automatic configuration needs the **Codex CLI**; a detected desktop/configuration folder alone is insufficient. Nonstandard profiles, Gemini custom context filenames and future client format changes may require manual configuration. The installer preserves unrelated settings and refuses malformed JSON or managed instruction markers.

The instruction block tells agents to search first, save concise durable verified knowledge, update existing entries with revision checks, preserve provenance and never submit credentials. It guides behavior but cannot force calls or override client permissions. There is no automatic import of previous conversations or separate Codex memory.

## Other local MCP clients

Use the Streamable HTTP endpoint:

```text
http://127.0.0.1:8765/mcp
```

Example for clients accepting a Cursor-style configuration:

```json
{
  "mcpServers": {
    "agent-brain": { "url": "http://127.0.0.1:8765/mcp" }
  }
}
```

Client formats differ; consult the client's documentation. Paste `BRAIN-INSTRUCTIONS.md` into its global instructions and use a stable project name such as `demo-shop` in searches and `project:demo-shop` when saving.

For stdio, use an absolute package path and Docker executable available to the client:

```text
docker compose --project-name agent-brain --project-directory <absolute-package-folder> --env-file <absolute-package-folder>/.env -f <absolute-package-folder>/compose.yaml exec -T mcp python server.py --stdio
```

The stack must already be running. Keep stdout available for MCP messages. Do not add credentials to this command. Moving the package folder requires updating stdio paths.

Cloud-only clients cannot directly reach your PC's localhost. Exposing this stack publicly needs a separate authenticated deployment design and is outside this package's scope.

## Check a connection

Ask the agent to call `brain_search` for project `demo` and report whether it received an empty list or knowledge. Then ask it to save a harmless fact for that project. The dashboard should show the entry. An empty list is a successful search, not an outage. The installer also provides `-Action Test` for real protocol/service checks.

## Client documentation

- [Codex MCP](https://developers.openai.com/codex/mcp) and [AGENTS.md](https://developers.openai.com/codex/guides/agents-md)
- [Claude Code MCP](https://code.claude.com/docs/en/mcp)
- [Gemini CLI MCP](https://geminicli.com/docs/tools/mcp-server/)
- [Cursor MCP](https://cursor.com/docs/mcp) and [Rules](https://cursor.com/docs/rules)
- [Claude Desktop local servers](https://modelcontextprotocol.io/docs/develop/connect-local-servers)
