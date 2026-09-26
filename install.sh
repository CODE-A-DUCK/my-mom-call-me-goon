#!/usr/bin/env bash
set -e
[ "$(id -u)" -ne 0 ] && echo "[-] Error: Please run as root!" && exit 1

printf 'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\nnet.core.rmem_max=16777216\nnet.core.wmem_max=16777216\nnet.ipv4.udp_rmem_min=8192\nnet.ipv4.udp_wmem_min=8192\nnet.ipv4.tcp_fastopen=3\n' > /etc/sysctl.d/pork.conf
sysctl --system > /dev/null 2>&1 || true

apt-get update -qq && apt-get install -y -qq curl openssl qrencode ufw > /dev/null 2>&1
curl -fsSL https://sing-box.app/deb-install.sh | bash > /dev/null 2>&1

ufw allow 22/tcp > /dev/null 2>&1 && ufw allow 443 > /dev/null 2>&1 && ufw --force enable > /dev/null 2>&1

UUID=$(sing-box generate uuid)
KEYS=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYS" | awk '/PrivateKey/{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | awk '/PublicKey/{print $2}')
SHORT_ID=$(openssl rand -hex 8)

mkdir -p /etc/sing-box
cat <<EOF > /etc/sing-box/config.json
{
  "log": { "level": "warn" },
  "inbounds": [{
    "type": "vless",
    "listen": "::",
    "listen_port": 443,
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
  }],
  "outbounds": [{ "type": "direct" }]
}
EOF

systemctl daemon-reload && systemctl enable --now sing-box && systemctl restart sing-box

SERVER_IP=$(curl -s4 https://api.ipify.org || curl -s4 https://ifconfig.me)
NODE_LINK="vless://${UUID}@${SERVER_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=gateway.icloud.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#codeaduck"

clear
cat <<EOF | tee /root/node_info.txt
*********************************************************
          DONE.
*********************************************************
Server IP : $SERVER_IP
Port  : 443
UUID     : $UUID
Public Key: $PUBLIC_KEY
Short ID : $SHORT_ID
Your mom's domain  : gateway.icloud.com

Import node link(You may copy into v2ray):
$NODE_LINK
*********************************************************
EOF

printf "\nUse mobile phone scan QRcode (v2rayNG / Shadowrocket / Sing-box)：\n\n"
qrencode -t ANSIUTF8 "$NODE_LINK"
echo ""
