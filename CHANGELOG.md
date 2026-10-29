# CHANGELOG

## 2026-10-29
- Server ordered and deployed: Cherry Servers Chicago, Threadripper PRO 7975WX / 768 GB / 2×1 TB + 2×4 TB NVMe, Ubuntu 24.04. Portal id 1048290, IP 84.32.63.98.
- Repo created (`thewhitewhale01/solana-node`, public — bootstrap is fetched from it; no secrets inside).
- Wrote `bootstrap.sh`: packages, Caddy, disk detect/format/mount (ledger, accounts), sysctl + nofile limits, swap off, `sol` user, Agave (stable channel via Anza installer), identity keypair, `sol.service`, ufw/fail2ban, node-admin MCP connector behind Caddy TLS on sslip.io, logrotate; starts the node.
- Wrote `node-admin/server.py` (mcp 2.x `MCPServer`, streamable HTTP, key in URL path): tools `run`, `run_background`, `job_status`, `read_file`, `write_file`, `tail`, `node_status`, `service`.
- Wrote `bin/validator.sh` (non-voting RPC flags; Geyser line commented for stage 2), systemd units, Caddyfile template, sysctl/limits/logrotate configs, OPS.md.

## 2026-10-29 (later)
- Fix: bootstrap aborted with `bad substitution` on the ADMIN_KEY length check under `set -u`.
