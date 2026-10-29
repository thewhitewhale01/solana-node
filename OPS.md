# OPS — Solana RPC node (state of the world)

_Last updated: 2026-10-29. Update this file after every change; append to CHANGELOG.md._

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
- Root password: Cherry portal (shown 24 h after each deploy/rebuild). Not needed for day-to-day ops; the connector is the control path.
- Provisioning: Cherry portal → Actions → Rebuild, with the first-boot script as **User data** (see `userdata.example.sh`). The portal's Rebuild button can sit on a spinner for minutes and may need a page reload + second submit; the server flips to *Deploying* when it has actually taken. No SSH or console needed.

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
