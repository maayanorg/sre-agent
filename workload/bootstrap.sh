#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nodejs curl jq dnsutils rsyslog stress-ng
install -d /opt/srelab /mnt/srelab-data
id srelab >/dev/null 2>&1 || useradd --system --home /opt/srelab --shell /usr/sbin/nologin srelab
if [ ! -f /opt/srelab/data.img ]; then
  truncate -s 128M /opt/srelab/data.img
  mkfs.ext4 -F -m 0 /opt/srelab/data.img
fi
grep -q '/mnt/srelab-data' /etc/fstab || echo '/opt/srelab/data.img /mnt/srelab-data ext4 loop,nosuid,nodev,noexec 0 0' >> /etc/fstab
mountpoint -q /mnt/srelab-data || mount /mnt/srelab-data
chown srelab:srelab /mnt/srelab-data
echo '__APP_BASE64__' | base64 -d > /opt/srelab/server.js
echo '__SHOP_BASE64__' | base64 -d > /opt/srelab/shop.cjs
cat > /opt/srelab/config.json <<'CONFIG'
{"role":"__ROLE__","release":"v1","backend":"http://backend.srelab.internal:8081","storage":"__STORAGE__","vault":"__VAULT__","clientId":"__CLIENT_ID__","resourceGroupId":"__RG_ID__"}
CONFIG
cp /opt/srelab/config.json /opt/srelab/config.baseline.json
cat > /etc/systemd/system/srelab.service <<'SERVICE'
[Unit]
Description=SRE lab application
After=network-online.target
RequiresMountsFor=/mnt/srelab-data
[Service]
User=srelab
ExecStart=/usr/bin/node /opt/srelab/server.js
Restart=on-failure
MemoryMax=384M
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=srelab-app
[Install]
WantedBy=multi-user.target
SERVICE
cat > /opt/srelab/probe.sh <<'PROBE'
#!/bin/bash
for endpoint in health storage vault arm; do
  code=$(curl -s -o /dev/null --max-time 25 -w '%{http_code}' "http://localhost:8080/$endpoint") || true
  logger -p local0.info -t srelab-probe "SRELAB endpoint=$endpoint status=$code"
done
PROBE
chmod +x /opt/srelab/probe.sh
cat > /etc/systemd/system/srelab-probe.service <<'SERVICE'
[Unit]
Description=SRE lab dependency probes
[Service]
Type=oneshot
ExecStart=/opt/srelab/probe.sh
SERVICE
cat > /etc/systemd/system/srelab-probe.timer <<'TIMER'
[Unit]
Description=SRE lab one-minute probes
[Timer]
OnBootSec=60
OnUnitActiveSec=60
[Install]
WantedBy=timers.target
TIMER
systemctl daemon-reload
systemctl enable --now rsyslog srelab
if [ '__ROLE__' = 'client' ]; then systemctl enable --now srelab-probe.timer; fi
touch /opt/srelab/bootstrap-complete