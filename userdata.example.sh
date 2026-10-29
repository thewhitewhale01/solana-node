#!/bin/bash
# Cherry "Rebuild" → User data. Replace <ADMIN_KEY> (openssl rand -hex 24) and <COMMIT>.
# Runs as root on first boot; the bootstrap is launched as its own transient systemd unit
# so it is independent of cloud-init's lifecycle. Progress markers: /root/userdata.status
export HOME=/root
echo "user-data started $(date -u +%FT%TZ)" > /root/userdata.status
cat > /root/run-bootstrap.sh <<'EOS'
#!/bin/bash
export HOME=/root ADMIN_KEY=<ADMIN_KEY> ADMIN_HOST=84-32-63-98.sslip.io
curl -fsSL --retry 10 --retry-delay 6 https://raw.githubusercontent.com/thewhitewhale01/solana-node/<COMMIT>/bootstrap.sh -o /root/bootstrap.sh
echo "fetched bootstrap: rc=$? $(date -u +%FT%TZ)" >> /root/userdata.status
bash /root/bootstrap.sh >/dev/null 2>&1
echo "bootstrap exited rc=$? $(date -u +%FT%TZ)" >> /root/userdata.status
EOS
chmod 0700 /root/run-bootstrap.sh
systemd-run --unit=solana-bootstrap --property=KillMode=process /root/run-bootstrap.sh
echo "unit launched $(date -u +%FT%TZ)" >> /root/userdata.status
