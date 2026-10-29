#!/bin/bash
export HOME=/root
mkdir -p /srv/bootlog
echo "user-data started $(date -u +%FT%TZ) pid=$$ uid=$(id -u)" > /srv/bootlog/status.txt
systemd-run --unit=bootlog-http --property=KillMode=process /usr/bin/python3 -m http.server 8010 --directory /srv/bootlog
cat > /root/run-bootstrap.sh <<'EOS'
#!/bin/bash
export HOME=/root ADMIN_KEY=<ADMIN_KEY> ADMIN_HOST=84-32-63-98.sslip.io
curl -fsSL --retry 10 --retry-delay 6 https://raw.githubusercontent.com/thewhitewhale01/solana-node/<COMMIT>/bootstrap.sh -o /root/bootstrap.sh
echo "fetched bootstrap: rc=$? $(wc -c < /root/bootstrap.sh 2>/dev/null) bytes $(date -u +%FT%TZ)" >> /srv/bootlog/status.txt
bash /root/bootstrap.sh >/dev/null 2>&1
echo "bootstrap exited rc=$? $(date -u +%FT%TZ)" >> /srv/bootlog/status.txt
EOS
chmod 0700 /root/run-bootstrap.sh
systemd-run --unit=bootlog-sync --property=KillMode=process /bin/bash -c 'while true; do sed "s/<ADMIN_KEY>/<KEY>/g" /var/log/solana-bootstrap.log > /srv/bootlog/bootstrap.log 2>/dev/null; cp /var/log/cloud-init-output.log /srv/bootlog/ 2>/dev/null; sleep 5; done'
systemd-run --unit=solana-bootstrap --property=KillMode=process /root/run-bootstrap.sh
echo "units launched $(date -u +%FT%TZ)" >> /srv/bootlog/status.txt
