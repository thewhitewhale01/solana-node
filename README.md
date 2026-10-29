# solana-node

Self-hosted, non-voting Solana mainnet RPC node (Agave) with a small MCP "node-admin" connector so the box
can be operated remotely from Claude. Ops state lives in [OPS.md](OPS.md); every change is logged in
[CHANGELOG.md](CHANGELOG.md).

## Bootstrap a fresh Ubuntu 24.04 bare-metal server

```bash
curl -fsSL https://raw.githubusercontent.com/thewhitewhale01/solana-node/main/bootstrap.sh \
  | ADMIN_KEY=<48-hex-random> bash
```

Prints the connector URL at the end (also in `/root/node-admin.url`). Idempotent; re-run safely.

## Layout

- `bootstrap.sh` — one-shot provisioning
- `bin/validator.sh` — the agave-validator flags (edit, then `systemctl restart sol.service`)
- `systemd/` — `sol.service`, `node-admin.service`
- `config/` — Caddyfile template, sysctl, nofile limits, logrotate
- `node-admin/` — MCP server (Python, `mcp>=2`)

No secrets are committed. The admin key is generated off-box and passed via `ADMIN_KEY` at bootstrap.
