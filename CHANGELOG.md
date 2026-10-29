# CHANGELOG

## 2026-10-29
- Server ordered and deployed: Cherry Servers Chicago, Threadripper PRO 7975WX / 768 GB / 2×1 TB + 2×4 TB NVMe, Ubuntu 24.04. Portal id 1048290, IP 84.32.63.98.
- Repo created (`thewhitewhale01/solana-node`, public — bootstrap is fetched from it; no secrets inside).
- Wrote `bootstrap.sh`: packages, Caddy, disk detect/format/mount (ledger, accounts), sysctl + nofile limits, swap off, `sol` user, Agave (stable channel via Anza installer), identity keypair, `sol.service`, ufw/fail2ban, node-admin MCP connector behind Caddy TLS on sslip.io, logrotate; starts the node.
- Wrote `node-admin/server.py` (mcp 2.x `MCPServer`, streamable HTTP, key in URL path): tools `run`, `run_background`, `job_status`, `read_file`, `write_file`, `tail`, `node_status`, `service`.
- Wrote `bin/validator.sh` (non-voting RPC flags; Geyser line commented for stage 2), systemd units, Caddyfile template, sysctl/limits/logrotate configs, OPS.md.

## 2026-10-29 (later)
- Fix: bootstrap aborted with `bad substitution` on the ADMIN_KEY length check under `set -u`.
- Fix: Caddy failed to start — `caddy validate` (run as root) created `/var/log/caddy/access.log` root-owned; bootstrap now chowns `/var/log/caddy` to caddy before starting.
- Fix: Anza's pre-built stable tarball (commit 0f131d3, Agave v4.3 line) no longer ships `agave-validator`. Bootstrap now installs build deps + rustup for `sol` and builds `agave-validator` from source at the exact pinned commit (`~/agave`, blobless clone), installing it into `active_release/bin`.
- Bootstrap now checks node-admin, caddy and sol.service individually and prints the failing unit's journal.
- Bootstrap: apt waits for the dpkg lock (first-boot unattended-upgrades); data disks already labeled LEDGER/ACCOUNTS are mounted instead of re-detected (survives an OS rebuild).
- Provisioning path switched to Cherry "Rebuild" with cloud-init user-data (no console/SSH needed): user-data fetches bootstrap.sh and runs it under nohup on first boot.
- 12:58 PT: Rebuild submitted from the portal with user-data (hostname kept as large-sawfly, monitoring enabled). First submit never sent a request (portal UI stuck on spinner); reload + resubmit worked. Server → Deploying.
- Bootstrap reordered: firewall + node-admin/Caddy now come up before the Agave build, so the connector is reachable during the long compile (previous order left ~20 min blind).
- 13:30 PT: first user-data run went idle after the apt step (CPU flat, connector never came up; cause unknown — connector was ordered after the build, so no log access). Bootstrap re-instrumented: output mirrored to /dev/tty1 (visible on the KVM without login), ERR trap prints the failing line, firewall+connector now run right after apt/repo (before disks), Agave fetched as a shallow single-commit fetch instead of a blobless clone, cargo output to ~sol/log/agave-build.log, key kept off the console.
