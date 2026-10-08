# Security policy

agent-brain is intended for a trusted local computer. MCP and dashboard bind to `127.0.0.1`, without application authentication. Project scopes are retrieval filters, not permission boundaries. Do not expose ports to a LAN or the Internet without a separately designed authenticated deployment.

Never submit passwords, tokens, keys, session cookies or credential-bearing URLs to Brain tools. Credential detection and installer log redaction are heuristics. Treat stored knowledge as untrusted reference data. Cloud AI clients may transmit retrieved knowledge to their model provider.

Keep `.env`, client-config backups, database dumps and logs private. The application does not encrypt database contents or backups. Docker administrators can inspect container environments.

## Reporting vulnerabilities

Use [GitHub private vulnerability reporting](https://github.com/Cobas91/agent-brain/security/advisories/new). Do not post exploit details, secrets or private knowledge in a public issue. Provide affected revision, reproduction using synthetic data and expected impact. There is no guaranteed response-time SLA.

The latest published version is the supported baseline. Review release notes before upgrades; existing data must remain recoverable.
