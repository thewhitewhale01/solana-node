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
- Found the first-boot failure: the Caddy repo step (`curl | gpg --dearmor`) dies when the cloudsmith key download returns nothing, which is the step right after apt. Now retried, validated, and falls back to Ubuntu's own caddy package.
- Attempt-3 user-data (`userdata.example.sh`) starts a boot-log HTTP server on :8010 (masked copy of the bootstrap log) and launches the bootstrap via `systemd-run` so it is independent of cloud-init's unit lifecycle.
- 13:4x PT: a boot-log HTTP server idea was dropped (unauthenticated public port); the TLS+key connector is the only control channel. Third rebuild submitted with the Caddy fix; user-data launches the bootstrap via `systemd-run` (detached from cloud-init) and records progress in /root/userdata.status.

## 2026-10-30
- 06:4x PT: Portal rebuilds (3x) never delivered user-data to the box (cloud-init reported none). Switched to the Cherry API: `POST /v1/servers/1048290/actions {type: rebuild, image: ubuntu_24_04_64bit, user_data: <base64>, metrics_install: true}` -> 201, status deploying. API constraints learned: password charset excludes quotes, backslash, backtick, `!$%&;#^`; `metrics_install` is a JSON boolean. API calls are made from the user's Chrome (sandbox egress is blocked); token lives in Cherry -> Settings -> API keys (`claude-ops`).
- Also learned: the box hung in BIOS POST (`DXE--AHCI Initialization`) for 20 min after one reinstall reboot; a Power Reset from the KVM cleared it.
- 07:14 PT: API rebuild #2 (5th rebuild overall): the 06:4x API rebuild also booted without running user-data — Cherry's rebuild path ignores user-data on this box regardless of channel. Added SSH key `claude-ops` (id 20456) to the account (user did it in the portal); rebuilt with `ssh_keys:[20456]` and a saved root password. Password rule learned: must contain a digit that is not the last character. Plan: log in with the key (or the saved password via KVM) and launch the bootstrap by hand once.
