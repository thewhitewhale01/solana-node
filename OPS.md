# OPS — Solana RPC node (state of the world)

_Last updated: 2026-10-30. Update this file after every change; append to CHANGELOG.md._

> **STATUS: no server.** The Cherry Servers box (id 1048290, 84.32.63.98) was cancelled on 2026-10-30 after five rebuilds in which Cherry's provisioning ignored user-data and the API-set password. Everything below describing that box is historical. The bootstrap, connector and validator config in this repo are provider-agnostic and ready for the next host; see "Next attempt" at the bottom.

## Purpose
Self-hosted, non-voting Solana mainnet RPC node. Replaces metered RPC vendors (Helius, Shyft) for all
on-chain reads and, in stage 2, streams every relevant transaction/account update via Yellowstone gRPC
into the data warehouse (ClickHouse on a DigitalOcean droplet, to be built).

## Hardware / hosting
- Provider: Cherry Servers, Chicago (US-Chicago). Plan: AMD Threadripper PRO 7975WX.
- 32c/64t @ 4.0–5.3 GHz · 768 GB DDR5 ECC · 2×1 TB NVMe (OS, RAID 1) · 2×4 TB NVMe (data) · 10 Gbps, 100 TB/mo egress
- Public IP: 84.32.63.98 · Private IP: 10.186.123.42 · Portal server id: 1048290 · hostname (portal): large-sawfly
- Billing: $1,461.33/mo monthly. 15-day money-back window from 2026-10-29.
- OS: Ubuntu 24.04 LTS

## Layout
| Path | What |
|---|---|
| `/mnt/ledger` (4 TB, ext4, label LEDGER) | RocksDB ledger, rolling (`--limit-ledger-size`) |
| `/mnt/accounts` (4 TB, ext4, label ACCOUNTS) | accounts DB |
| `/home/sol/snapshots` (on OS mirror) | full + incremental snapshots |
| `/home/sol/log/validator.log` | validator log (logrotate daily / 2 GB) |
| `/home/sol/bin/validator.sh` | **the flags**. Edit → `systemctl restart sol.service` |
| `/home/sol/validator-keypair.json` | node identity (unfunded; non-voting) |
| `/opt/solana-node` | clone of this repo on the box |
| `/home/sol/agave` | Agave source checkout (built at the installer's pinned commit; `agave-validator` is no longer shipped pre-built) |
| `/home/sol/.cargo`, `~/.rustup` | Rust toolchain for `sol` (needed for Agave + Yellowstone builds) |
| `/opt/node-admin`, `/etc/node-admin/env` | node-admin MCP connector + its key |
| `/var/log/node-admin/` | connector call log, background job logs |
| `/var/log/solana-bootstrap.log` | bootstrap output |

## Services
- `sol.service` — agave-validator as user `sol` (Restart=always, SIGINT stop, 300 s stop timeout)
- `node-admin.service` — MCP connector on 127.0.0.1:8808, path `/k/<KEY>/mcp`
- `caddy` — TLS on `84-32-63-98.sslip.io` → proxies `/k/*` to node-admin, 404 everything else
- `chrony`, `fail2ban`, `ufw`

## Network / firewall (ufw)
- In: 22/tcp, 80/tcp (ACME), 443/tcp (connector), 8000–8020 tcp+udp (gossip/turbine/repair)
- RPC 8899 / WS 8900 bound to 127.0.0.1 only (`--private-rpc`). Not reachable from outside by design.
- No SSH from Claude's environments (egress policy) → all operation goes through the node-admin connector.
  Fallback: Cherry portal → Console (IP-KVM).

## Validator flags (summary — source of truth is bin/validator.sh)
non-voting · known-validator snapshot trust (`--only-known-rpc`) · full RPC API · tx history + extended
metadata · account indexes: program-id, spl-token-owner, spl-token-mint · dynamic ports 8000–8020 ·
default ledger size limit · Geyser plugin line present but commented out (stage 2)

## Access
- Claude connector: `https://84-32-63-98.sslip.io/k/<KEY>/mcp` (key in `/etc/node-admin/env` and `/root/node-admin.url`; never commit it)
- Root password: set by the API rebuild call; Claude keeps it in its workspace (`~/.config/cherry/root_password_1048290`), the portal does not show API-set passwords. SSH key `claude-ops` (ed25519, Cherry key id 20456) is attached at rebuild; private half in Claude's workspace. Day-to-day control path is still the node-admin connector.
- Provisioning: **use the Cherry API, not the portal's Rebuild dialog** — the portal never delivered user-data to the machine in three attempts. `POST https://api.cherryservers.com/v1/servers/1048290/actions` with `{type:"rebuild", image:"ubuntu_24_04_64bit", hostname, password, os_disk:"NVMe 1TB", os_raid_level:"Raid 1", os_partition_size:1024, user_data:<base64 of userdata.example.sh>, metrics_install:true}`. Bearer token: Cherry portal → Settings → API keys (`claude-ops`). Password must avoid quotes, backslash, backtick and `!$%&;#^`, and contain a digit that is not the last character. **User-data has never run on this box via portal or API (5 rebuilds)** — always attach `ssh_keys:[20456]` (claude-ops) so the box is reachable, and launch `userdata.example.sh` by hand. Other actions: `reboot`, `power-off`, `power-on`, `enter-rescue-mode`, `create-console-access`.
- If the box hangs in BIOS POST after a reinstall (`DXE--AHCI Initialization` for minutes), send a Power Reset from the KVM power menu or `{type:"reboot"}` via the API.

## Stage 2 — TODO
- [ ] Build Yellowstone gRPC Geyser plugin matching `agave-validator --version`; config at `/home/sol/yellowstone/config.json`; uncomment flag; restart
- [ ] Expose gRPC (10000) to the warehouse droplet only (WireGuard or Caddy mTLS)
- [ ] DigitalOcean droplet: ClickHouse + consumer + Parquet→Spaces tiering
- [ ] Swap sslip.io host for a real subdomain (Namecheap A record) if desired
- [ ] Health check scheduled task (report when catch-up slips or a service dies)

## Known gotchas
- Pre-built Cherry configs can't change RAM/disks in place — growth = rebuild onto a bigger plan.
- Geyser plugin must be built against the exact Agave version; upgrading Agave = rebuild plugin.
- `agave-validator` is built from source (Anza stopped shipping it in the release tarball). Upgrade = `agave-install update` for the tools, then rebuild the validator at the new pinned commit (bootstrap does this automatically when the binary is missing; delete it to force).
- First start: snapshot download + account index build takes 1–3 h; `getHealth` returns "behind" until caught up.

## Next attempt — requirements for the host (learned the hard way)
- Must provision like DigitalOcean: root SSH with a key or a password the portal actually shows, reachable within minutes of creation. Cloud-init/user-data that demonstrably runs, or no reliance on it.
- Claude's environments cannot open SSH; the control path is the node-admin connector (HTTPS + key in URL). Bring the connector up **first** in the bootstrap, before any long build, so the box is operable within ~3 minutes.
- Bare metal is still required for a Solana node (512 GB+ RAM, 2× 4 TB NVMe, 10 Gbps). Candidates with DO-like tooling: Latitude.sh (API, `lsh` CLI, Terraform, serial console over SSH, rescue mode), Edgevana, PureVoltage. Verify on day one, before anything else, that user-data or SSH keys actually land on the box.
- Keep `bin/validator.sh`, `node-admin/`, `systemd/`, `config/` as-is; `bootstrap.sh` needs only host-specific disk detection re-checked (it keys on two blank ~4 TB NVMe drives).
