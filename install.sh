#!/usr/bin/env bash
set -e
[ "$(id -u)" -ne 0 ] && echo "[-] Error: Please run as root!" && exit 1

cat > /etc/sysctl.d/pork.conf << 'SYSCTL'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_autocorking=0
net.ipv4.tcp_syn_retries=2
net.ipv4.tcp_synack_retries=2
net.ipv4.tcp_fin_timeout=10
net.ipv4.tcp_tw_reuse=1
net.core.netdev_max_backlog=32768
net.core.somaxconn=32768
net.ipv4.tcp_max_syn_backlog=16384
SYSCTL
sysctl --system > /dev/null 2>&1 || true

apt-get update -qq && apt-get install -y -qq curl openssl qrencode ufw > /dev/null 2>&1
curl -fsSL https://sing-box.app/deb-install.sh | bash > /dev/null 2>&1

ufw allow 22/tcp  > /dev/null 2>&1
ufw allow 443     > /dev/null 2>&1
ufw --force enable > /dev/null 2>&1

UUID=$(sing-box generate uuid)
KEYS=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYS" | awk '/PrivateKey/{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | awk '/PublicKey/{print $2}')
SHORT_ID=$(openssl rand -hex 8)
HY2_PASS=$(openssl rand -hex 16)

mkdir -p /etc/sing-box
openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
  -keyout /etc/sing-box/hy2.key \
  -out    /etc/sing-box/hy2.crt \
  -days 3650 -subj "/CN=gateway.icloud.com" 2>/dev/null

cat <<EOF > /etc/sing-box/config.json
{
  "log": { "level": "warn" },
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": 443,
      "tcp_fast_open": true,
      "users": [{ "uuid": "$UUID", "flow": "xtls-rprx-vision" }],
      "tls": {
        "enabled": true,
        "server_name": "gateway.icloud.com",
        "reality": {
          "enabled": true,
          "handshake": { "server": "gateway.icloud.com", "server_port": 443 },
          "private_key": "$PRIVATE_KEY",
          "short_id": ["$SHORT_ID"]
        }
      }
    },
    {
      "type": "hysteria2",
      "listen": "::",
      "listen_port": 443,
      "users": [{ "password": "$HY2_PASS" }],
      "tls": {
        "enabled": true,
        "certificate_path": "/etc/sing-box/hy2.crt",
        "key_path": "/etc/sing-box/hy2.key"
      }
    }
  ],
  "outbounds": [{ "type": "direct" }]
}
EOF

systemctl daemon-reload && systemctl enable --now sing-box && systemctl restart sing-box

SERVER_IP=$(curl -s4 https://api.ipify.org || curl -s4 https://ifconfig.me)

VLESS_LINK="vless://${UUID}@${SERVER_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=gateway.icloud.com&fp=firefox&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&tfo=1#codeaduck-vless"
HY2_LINK="hysteria2://${HY2_PASS}@${SERVER_IP}:443?insecure=1&sni=gateway.icloud.com#codeaduck-hy2"

clear
cat <<EOF | tee /root/node_info.txt
*********************************************************
          DONE.
*********************************************************
Server IP  : $SERVER_IP
Port       : 443 (TCP=VLESS, UDP=Hysteria2)

── VLESS + XTLS-Vision + Reality (TCP) ─────────────────
UUID       : $UUID
Public Key : $PUBLIC_KEY
Short ID   : $SHORT_ID
SNI        : gateway.icloud.com
$VLESS_LINK

── Hysteria2 (UDP) ──────────────────────────────────────
Password   : $HY2_PASS
$HY2_LINK
*********************************************************
EOF

printf "\n[VLESS] QR Code (v2rayNG / Shadowrocket / Sing-box):\n\n"
qrencode -t ANSIUTF8 "$VLESS_LINK"

printf "\n[Hysteria2] QR Code (Sing-box / Hiddify / NekoBox):\n\n"
qrencode -t ANSIUTF8 "$HY2_LINK"

echo ""
