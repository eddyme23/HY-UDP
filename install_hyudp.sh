#!/bin/bash
# Ultimate Hysteria UDP VPN Installer
# Features: Auto-SSL, QoS Bypass, Kernel Tuning, IPv6 Support
# Author: Eddyme23
# Version: 2.0

# Configuration (Customize These!)
DOMAIN="vpn.khaledagn.com"          # Your domain or server IP
PORT="36712"                     # Default: 36712 (UDP)
PASSWORD="vpnxXEdyln"            # Auth password
OBFS="vpnxXEdyln"                # Obfuscation password
UP_MBPS="0"                      # 0 = unlimited (set to 90% of ISP limit if throttled)
DOWN_MBPS="0"                    # 0 = unlimited
IPV6="true"                      # Enable IPv6? (true/false)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root${NC}" 
    exit 1
fi

# Header
echo -e "${GREEN}"
cat << "EOF"
  _    _           _   _             
 | |  | |         | | (_)            
 | |__| |_   _ ___| |_ _ _ __   __ _ 
 |  __  | | | / __| __| | '_ \ / _` |
 | |  | | |_| \__ \ |_| | | | | (_| |
 |_|  |_|\__,_|___/\__|_|_| |_|\__, |
                                 __/ |
                                |___/ 
EOF
echo -e "${NC}"

# Dependency Installation
echo -e "${YELLOW}[+] Installing dependencies...${NC}"
apt update
apt install -y wget curl openssl iptables-persistent netfilter-persistent qrencode

# Detect Architecture
ARCH=$(uname -m)
case $ARCH in
    "x86_64") ARCH="amd64" ;;
    "aarch64") ARCH="arm64" ;;
    "armv7l") ARCH="arm" ;;
    *) echo -e "${RED}Unsupported architecture: $ARCH${NC}"; exit 1 ;;
esac

# Download Hysteria
echo -e "${YELLOW}[+] Downloading Hysteria...${NC}"
LATEST_VER=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep tag_name | cut -d '"' -f 4)
HYSTERIA_URL="https://github.com/apernet/hysteria/releases/download/$LATEST_VER/hysteria-linux-$ARCH"
wget -O /usr/local/bin/hysteria "$HYSTERIA_URL" || { echo -e "${RED}Failed to download Hysteria${NC}"; exit 1; }
chmod +x /usr/local/bin/hysteria

# Create Config Directory
mkdir -p /etc/hysteria

# Generate SSL Certificates
echo -e "${YELLOW}[+] Generating SSL certificates...${NC}"
openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/server.key
openssl req -new -x509 -days 36500 -key /etc/hysteria/server.key -out /etc/hysteria/server.crt -subj "/CN=$DOMAIN"

# Create Config File
echo -e "${YELLOW}[+] Creating config file...${NC}"
cat > /etc/hysteria/config.json <<EOF
{
    "listen": ":$PORT",
    "protocol": "udp",
    "cert": "/etc/hysteria/server.crt",
    "key": "/etc/hysteria/server.key",
    "up_mbps": $UP_MBPS,
    "down_mbps": $DOWN_MBPS,
    "obfs": "$OBFS",
    "alpn": "h3",
    "disable_udp": false,
    "auth": {
        "mode": "passwords",
        "config": ["$PASSWORD"]
    }
}
EOF

# Enable IPv6 if requested
if [[ "$IPV6" == "true" ]]; then
    echo -e "${YELLOW}[+] Enabling IPv6 support...${NC}"
    sysctl -w net.ipv6.conf.all.disable_ipv6=0
    sysctl -w net.ipv6.conf.default.disable_ipv6=0
    sed -i '/"listen":/s/":/"[::]:/' /etc/hysteria/config.json
fi

# Kernel Optimization
echo -e "${YELLOW}[+] Optimizing kernel settings...${NC}"
cat >> /etc/sysctl.conf <<EOF
# Hysteria Optimizations
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.udp_mem=16777216 16777216 16777216
net.ipv4.tcp_congestion_control=bbr
net.core.default_qdisc=fq
EOF
sysctl -p

# Firewall Configuration
echo -e "${YELLOW}[+] Configuring firewall...${NC}"
iptables -A INPUT -p udp --dport $PORT -j ACCEPT
ip6tables -A INPUT -p udp --dport $PORT -j ACCEPT
iptables -t nat -A PREROUTING -i $(ip route | grep default | awk '{print $5}') -p udp --dport 10000:65000 -j DNAT --to-destination :$PORT
netfilter-persistent save

# Systemd Service
echo -e "${YELLOW}[+] Creating systemd service...${NC}"
cat > /etc/systemd/system/hysteria.service <<EOF
[Unit]
Description=Hysteria VPN Server
After=network.target

[Service]
User=root
WorkingDirectory=/etc/hysteria
ExecStart=/usr/local/bin/hysteria -config /etc/hysteria/config.json server
Restart=always
RestartSec=3
LimitNOFILE=infinity
Environment="HYSTERIA_LOG_LEVEL=info"

[Install]
WantedBy=multi-user.target
EOF

# Start Service
systemctl daemon-reload
systemctl enable hysteria
systemctl start hysteria

# Client Configuration
echo -e "${GREEN}"
echo "==============================================="
echo " Hysteria VPN Installed Successfully!"
echo "==============================================="
echo -e "${NC}"
echo -e "${YELLOW}Server IP:${NC} $(curl -4s ifconfig.co)"
echo -e "${YELLOW}Domain:${NC} $DOMAIN"
echo -e "${YELLOW}Port:${NC} $PORT"
echo -e "${YELLOW}Password:${NC} $PASSWORD"
echo -e "${YELLOW}Obfuscation:${NC} $OBFS"
echo -e "${YELLOW}IPv6 Support:${NC} $IPV6"
echo ""

# Generate QR Code for Mobile Clients
echo -e "${YELLOW}Mobile Client QR Code (Scan with Hysteria app):${NC}"
qrencode -t ANSIUTF8 "hy://$PASSWORD@$(curl -4s ifconfig.co):$PORT/?insecure=1&obfs=$OBFS&upmbps=$UP_MBPS&downmbps=$DOWN_MBPS"

echo -e "${GREEN}"
echo "==============================================="
echo " Client Configuration (JSON):"
echo "==============================================="
echo -e "${NC}"
cat <<EOF
{
    "server": "$DOMAIN:$PORT",
    "protocol": "udp",
    "up_mbps": $UP_MBPS,
    "down_mbps": $DOWN_MBPS,
    "obfs": "$OBFS",
    "password": "$PASSWORD",
    "insecure": true,
    "socks5": {
        "listen": "127.0.0.1:1080"
    }
}
EOF

echo -e "${GREEN}"
echo "==============================================="
echo -e "${NC}"
