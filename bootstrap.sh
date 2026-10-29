#!/usr/bin/env bash
# bootstrap.sh — turn a fresh Ubuntu 24.04 bare-metal box into a non-voting Solana RPC node
# with a node-admin MCP connector for remote operation.
#
# Usage (as root, on the server):
#   curl -fsSL https://raw.githubusercontent.com/thewhitewhale01/solana-node/main/bootstrap.sh \
#     | ADMIN_KEY=<48-hex> bash
#
# Optional env:
#   ADMIN_HOST   public hostname for the admin connector (default: <ip-with-dashes>.sslip.io)
#   REPO_URL     git URL of this repo (default: public GitHub)
#   SKIP_FORMAT  set to 1 to skip disk detection/formatting (disks already mounted)
#
# Idempotent: safe to re-run. Only formats a disk if it has NO filesystem signature.

set -Eeuo pipefail

REPO_URL="${REPO_URL:-https://github.com/thewhitewhale01/solana-node.git}"
REPO_DIR=/opt/solana-node
SOL_USER=sol
SOL_HOME=/home/sol
LEDGER=/mnt/ledger
ACCOUNTS=/mnt/accounts
SNAPSHOTS=$SOL_HOME/snapshots
LOG=/var/log/solana-bootstrap.log

exec > >(tee -a "$LOG") 2>&1
echo "=== solana-node bootstrap started $(date -u +%FT%TZ) ==="

die() { echo "FATAL: $*" >&2; exit 1; }
step() { echo; echo "--- $* ---"; }

[[ $EUID -eq 0 ]] || die "run as root"
grep -q 'VERSION_ID="24.04"' /etc/os-release || die "expected Ubuntu 24.04"
[[ ${#ADMIN_KEY:-} -ge 32 ]] || die "ADMIN_KEY env var (>=32 chars) is required"

PUBLIC_IP=$(curl -4 -fsS --max-time 10 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
ADMIN_HOST="${ADMIN_HOST:-$(echo "$PUBLIC_IP" | tr . -).sslip.io}"
echo "public ip: $PUBLIC_IP   admin host: $ADMIN_HOST"

# ------------------------------------------------------------------ packages
step "apt packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q curl wget git jq bzip2 htop iotop sysstat nvme-cli chrony ufw fail2ban \
  python3 python3-venv python3-pip logrotate unzip ca-certificates gnupg apt-transport-https \
  debian-keyring debian-archive-keyring linux-tools-common "linux-tools-$(uname -r)" 2>/dev/null || \
apt-get install -y -q curl wget git jq bzip2 htop iotop sysstat nvme-cli chrony ufw fail2ban \
  python3 python3-venv python3-pip logrotate unzip ca-certificates gnupg apt-transport-https \
  debian-keyring debian-archive-keyring

# Caddy (official repo)
if ! command -v caddy >/dev/null; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -q && apt-get install -y -q caddy
fi

# ------------------------------------------------------------------ repo
step "repo -> $REPO_DIR"
if [[ -d $REPO_DIR/.git ]]; then
  git -C "$REPO_DIR" pull -q --ff-only || true
else
  git clone -q "$REPO_URL" "$REPO_DIR"
fi

# ------------------------------------------------------------------ disks
step "data disks"
mkdir -p "$LEDGER" "$ACCOUNTS"
if [[ "${SKIP_FORMAT:-0}" != "1" ]]; then
  # Candidate: nvme disk, 3.5–4.1 TB, no partitions, no holders (not in md RAID), no fs signature.
  mapfile -t CANDIDATES < <(
    lsblk -dnb -o NAME,SIZE,TYPE | awk '$3=="disk" && $1 ~ /^nvme/ && $2>3500000000000 && $2<4100000000000 {print $1}' |
    while read -r d; do
      if [[ -z "$(lsblk -n /dev/"$d" | tail -n +2)" ]] && [[ -z "$(blkid -o value -s TYPE /dev/"$d" 2>/dev/null)" ]] && ! grep -q "$d" /proc/mdstat; then
        echo "$d"
      fi
    done
  )
  echo "blank 4TB nvme candidates: ${CANDIDATES[*]:-none}"
  if ! mountpoint -q "$LEDGER" || ! mountpoint -q "$ACCOUNTS"; then
    [[ ${#CANDIDATES[@]} -ge 2 ]] || die "need two blank ~4TB NVMe disks for ledger+accounts (found ${#CANDIDATES[@]}). Mount them manually and re-run with SKIP_FORMAT=1."
    for pair in "LEDGER:${CANDIDATES[0]}:$LEDGER" "ACCOUNTS:${CANDIDATES[1]}:$ACCOUNTS"; do
      IFS=: read -r label dev mnt <<<"$pair"
      if ! mountpoint -q "$mnt"; then
        echo "formatting /dev/$dev as ext4 ($label)"
        mkfs.ext4 -F -q -m 0 -L "$label" -E lazy_itable_init=0,lazy_journal_init=0 "/dev/$dev"
        uuid=$(blkid -o value -s UUID "/dev/$dev")
        grep -q "$uuid" /etc/fstab || echo "UUID=$uuid $mnt ext4 defaults,noatime,nodiratime,nofail 0 2" >> /etc/fstab
        mount "$mnt"
      fi
    done
  fi
fi
mountpoint -q "$LEDGER" || die "$LEDGER not mounted"
mountpoint -q "$ACCOUNTS" || die "$ACCOUNTS not mounted"
df -h "$LEDGER" "$ACCOUNTS"

# ------------------------------------------------------------------ kernel / limits
step "sysctl + limits"
install -m 0644 "$REPO_DIR/config/99-solana.conf" /etc/sysctl.d/99-solana.conf
sysctl -p /etc/sysctl.d/99-solana.conf >/dev/null
install -m 0644 "$REPO_DIR/config/90-solana-nofiles.conf" /etc/security/limits.d/90-solana-nofiles.conf
mkdir -p /etc/systemd/system.conf.d
printf '[Manager]\nDefaultLimitNOFILE=2000000\n' > /etc/systemd/system.conf.d/90-solana-nofiles.conf
systemctl daemon-reexec
# performance governor (best effort; amd_pstate may ignore)
(command -v cpupower >/dev/null && cpupower frequency-set -g performance >/dev/null 2>&1) || true
# chrony on, swap off (Agave wants RAM, not swap)
systemctl enable --now chrony >/dev/null 2>&1 || true
swapoff -a || true
sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab

# ------------------------------------------------------------------ sol user + agave
step "sol user + Agave"
id "$SOL_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$SOL_USER"
mkdir -p "$SOL_HOME/log" "$SNAPSHOTS" "$SOL_HOME/bin"
chown -R "$SOL_USER:$SOL_USER" "$SOL_HOME" "$LEDGER" "$ACCOUNTS"

if ! sudo -u "$SOL_USER" -H bash -lc 'command -v agave-validator' >/dev/null 2>&1; then
  sudo -u "$SOL_USER" -H bash -lc 'sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"'
fi
SOL_BIN="$SOL_HOME/.local/share/solana/install/active_release/bin"
grep -q 'solana/install/active_release/bin' "$SOL_HOME/.profile" || \
  echo "export PATH=\"$SOL_BIN:\$PATH\"" >> "$SOL_HOME/.profile"
# make the binaries visible system-wide too (root tooling, node-admin)
for b in agave-validator solana solana-keygen agave-ledger-tool; do
  ln -sf "$SOL_BIN/$b" /usr/local/bin/$b
done
echo "agave: $(sudo -u $SOL_USER -H "$SOL_BIN/agave-validator" --version)"

[[ -f $SOL_HOME/validator-keypair.json ]] || \
  sudo -u "$SOL_USER" -H "$SOL_BIN/solana-keygen" new --no-bip39-passphrase -s -o "$SOL_HOME/validator-keypair.json"
echo "identity: $(sudo -u $SOL_USER -H "$SOL_BIN/solana-keygen" pubkey "$SOL_HOME/validator-keypair.json")"

install -m 0755 -o "$SOL_USER" -g "$SOL_USER" "$REPO_DIR/bin/validator.sh" "$SOL_HOME/bin/validator.sh"
install -m 0644 "$REPO_DIR/systemd/sol.service" /etc/systemd/system/sol.service
install -m 0644 "$REPO_DIR/config/logrotate-sol" /etc/logrotate.d/sol

# ------------------------------------------------------------------ firewall
step "firewall"
ufw --force reset >/dev/null
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow 22/tcp >/dev/null            # ssh (console/rescue)
ufw allow 80/tcp >/dev/null            # caddy ACME http-01
ufw allow 443/tcp >/dev/null           # node-admin connector (caddy)
ufw allow 8000:8020/tcp >/dev/null     # gossip / tvu / repair / serve-repair
ufw allow 8000:8020/udp >/dev/null
# 8899/8900 (RPC/WS) stay closed; the validator binds them to 127.0.0.1 anyway
ufw --force enable >/dev/null
systemctl enable --now fail2ban >/dev/null 2>&1 || true
ufw status | head -20

# ------------------------------------------------------------------ node-admin
step "node-admin connector"
mkdir -p /opt/node-admin /etc/node-admin /var/log/node-admin
if [[ ! -x /opt/node-admin/venv/bin/python ]]; then
  python3 -m venv /opt/node-admin/venv
fi
/opt/node-admin/venv/bin/pip install -q --upgrade pip
/opt/node-admin/venv/bin/pip install -q -r "$REPO_DIR/node-admin/requirements.txt"
install -m 0755 "$REPO_DIR/node-admin/server.py" /opt/node-admin/server.py
cat > /etc/node-admin/env <<EOF
ADMIN_KEY=$ADMIN_KEY
ADMIN_HOST=$ADMIN_HOST
BIND_HOST=127.0.0.1
BIND_PORT=8808
EOF
chmod 0600 /etc/node-admin/env
install -m 0644 "$REPO_DIR/systemd/node-admin.service" /etc/systemd/system/node-admin.service

sed "s/__ADMIN_HOST__/$ADMIN_HOST/g" "$REPO_DIR/config/Caddyfile.tmpl" > /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile >/dev/null
systemctl daemon-reload
systemctl enable --now node-admin.service
systemctl restart caddy
sleep 2
systemctl is-active node-admin.service caddy

# ------------------------------------------------------------------ start the node
step "start sol.service"
systemctl enable sol.service >/dev/null
systemctl restart sol.service
sleep 5
systemctl is-active sol.service || { journalctl -u sol.service -n 50 --no-pager; die "sol.service failed to start"; }

# ------------------------------------------------------------------ done
step "DONE"
cat <<EOF

  node-admin connector URL (add in Claude → Settings → Connectors → Add custom connector):

      https://$ADMIN_HOST/k/$ADMIN_KEY/mcp

  Saved to /root/node-admin.url
  Validator log:  $SOL_HOME/log/validator.log      Bootstrap log: $LOG
  Ledger: $LEDGER   Accounts: $ACCOUNTS   Snapshots: $SNAPSHOTS

  The node is now downloading a snapshot and catching up (expect 1–3 hours).
  TLS for $ADMIN_HOST is issued on first request; give Caddy a minute.
EOF
echo "https://$ADMIN_HOST/k/$ADMIN_KEY/mcp" > /root/node-admin.url
chmod 0600 /root/node-admin.url
echo "=== bootstrap finished $(date -u +%FT%TZ) ==="
