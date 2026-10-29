#!/bin/bash
# Cherry "Rebuild" → User data. Replace <ADMIN_KEY> with 48 hex chars (openssl rand -hex 24)
# and <COMMIT> with the solana-node commit to provision from. Runs as root on first boot.
export ADMIN_KEY=<ADMIN_KEY>
export ADMIN_HOST=84-32-63-98.sslip.io
curl -fsSL --retry 10 --retry-delay 6 https://raw.githubusercontent.com/thewhitewhale01/solana-node/<COMMIT>/bootstrap.sh -o /root/bootstrap.sh
chmod 0700 /root/bootstrap.sh
nohup bash /root/bootstrap.sh >/dev/null 2>&1 &
