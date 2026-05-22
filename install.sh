#!/bin/bash
#===================================================
# 蓝多依诺 VPS 一键部署脚本 (官方 sing-box + WARP + Argo)
# 协议: VLESS + HTTPUpgrade， WARP 通过 WireGuard 端点出站
#===================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[信息]${NC} $1"; }
warn() { echo -e "${YELLOW}[警告]${NC} $1"; }
error() { echo -e "${RED}[错误]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && error "请使用 root 权限运行该脚本"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        warn "当前系统为 $ID，脚本仅测试过 Debian/Ubuntu"
    fi
else
    error "无法识别操作系统"
fi

info "更新软件包列表..."
apt update -qq
info "安装基础依赖 (curl, screen, jq, uuid-runtime)..."
apt install -y -qq curl screen jq uuid-runtime

# ----- 使用官方脚本安装 sing-box -----
if ! command -v sing-box &> /dev/null; then
    info "安装官方 sing-box..."
    curl -fsSL https://sing-box.app/install.sh | sh
    # 官方安装后可能在 /usr/local/bin，检查一下
    if ! command -v sing-box &> /dev/null; then
        error "sing-box 安装失败，请检查网络或手动安装"
    fi
else
    info "sing-box 已安装，版本: $(sing-box version | head -1)"
fi

# ----- 创建配置目录 -----
mkdir -p /etc/sing-box

echo ""
echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}  蓝多依诺 VPS 一键部署脚本${NC}"
echo -e "${BLUE}===========================================${NC}"
echo ""

# ----- 交互式参数收集 -----
# 第1步: WARP 配置
echo -e "${YELLOW}【第 1 步】WARP WireGuard 配置${NC}"
echo "请粘贴从 WARP 生成网站获取的配置信息"
read -p "WARP PrivateKey: " WARP_PRIVATE_KEY
[[ -z "$WARP_PRIVATE_KEY" ]] && error "WARP PrivateKey 不能为空"

read -p "WARP PublicKey (默认: bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=): " WARP_PUBLIC_KEY
WARP_PUBLIC_KEY=${WARP_PUBLIC_KEY:-"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="}

read -p "WARP IPv4 Address (默认: 172.16.0.2/32): " WARP_IPV4
WARP_IPV4=${WARP_IPV4:-"172.16.0.2/32"}

read -p "WARP IPv6 Address: " WARP_IPV6
[[ -z "$WARP_IPV6" ]] && error "WARP IPv6 Address 不能为空"

read -p "WARP Endpoint (默认: engage.cloudflareclient.com:2408): " WARP_ENDPOINT
WARP_ENDPOINT=${WARP_ENDPOINT:-"engage.cloudflareclient.com:2408"}

read -p "WARP Reserved (三个数字，用逗号分隔，如 92,168,130): " WARP_RESERVED
[[ -z "$WARP_RESERVED" ]] && WARP_RESERVED="92,168,130"
WARP_RESERVED1=$(echo $WARP_RESERVED | cut -d, -f1)
WARP_RESERVED2=$(echo $WARP_RESERVED | cut -d, -f2)
WARP_RESERVED3=$(echo $WARP_RESERVED | cut -d, -f3)

echo ""

# 第2步: VLESS + HTTPUpgrade 配置
echo -e "${YELLOW}【第 2 步】VLESS + HTTPUpgrade 配置${NC}"
DEFAULT_UUID=$(uuidgen)
read -p "VLESS UUID (回车自动生成): " VLESS_UUID
VLESS_UUID=${VLESS_UUID:-$DEFAULT_UUID}

DEFAULT_PATH="/$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)"
read -p "HTTPUpgrade 路径 (回车自动生成): " HTTPUPGRADE_PATH
HTTPUPGRADE_PATH=${HTTPUPGRADE_PATH:-$DEFAULT_PATH}

read -p "sing-box 监听端口 (默认 8080): " LISTEN_PORT
LISTEN_PORT=${LISTEN_PORT:-8080}
echo ""

# 第3步: Argo 隧道配置
echo -e "${YELLOW}【第 3 步】Argo 隧道配置${NC}"
read -p "Argo 域名 (如 us3.989269.xyz): " ARGO_DOMAIN
[[ -z "$ARGO_DOMAIN" ]] && error "Argo 域名不能为空"

read -p "Argo 隧道 Token (eyJ...): " ARGO_TOKEN
[[ -z "$ARGO_TOKEN" ]] && error "Argo 隧道 Token 不能为空"
echo ""

# ----- 配置确认 -----
echo -e "${YELLOW}【配置确认】${NC}"
echo "WARP PrivateKey : ${WARP_PRIVATE_KEY:0:20}..."
echo "WARP PublicKey  : ${WARP_PUBLIC_KEY:0:20}..."
echo "WARP IPv4       : $WARP_IPV4"
echo "WARP IPv6       : $WARP_IPV6"
echo "WARP Endpoint   : $WARP_ENDPOINT"
echo "WARP Reserved   : $WARP_RESERVED"
echo "VLESS UUID      : $VLESS_UUID"
echo "HTTPUpgrade 路径: $HTTPUPGRADE_PATH"
echo "监听端口        : $LISTEN_PORT"
echo "Argo 域名       : $ARGO_DOMAIN"
echo "Argo Token      : ${ARGO_TOKEN:0:20}..."
read -p "确认无误？(Y/n): " confirm
[[ "$confirm" != "Y" && "$confirm" != "y" && "$confirm" != "" ]] && { info "已取消部署"; exit 0; }

# ----- 生成 sing-box 配置文件 -----
info "生成 /etc/sing-box/config.json ..."
cat > /etc/sing-box/config.json <<EOF
{
  "log": { "level": "info", "timestamp": true },
  "dns": {
    "servers": [
      { "tag": "dns_remote", "type": "udp", "server": "1.1.1.1", "detour": "warp-out" },
      { "tag": "dns_local", "type": "udp", "server": "2606:4700:4700::1111" }
    ],
    "strategy": "prefer_ipv6"
  },
  "endpoints": [
    {
      "type": "wireguard",
      "tag": "warp-out",
      "address": ["$WARP_IPV4", "$WARP_IPV6"],
      "private_key": "$WARP_PRIVATE_KEY",
      "peers": [
        {
          "address": "$WARP_ENDPOINT",
          "port": 2408,
          "public_key": "$WARP_PUBLIC_KEY",
          "reserved": [$WARP_RESERVED1, $WARP_RESERVED2, $WARP_RESERVED3],
          "allowed_ips": ["0.0.0.0/0", "::/0"]
        }
      ],
      "mtu": 1280
    }
  ],
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "127.0.0.1",
      "listen_port": $LISTEN_PORT,
      "users": [{ "uuid": "$VLESS_UUID" }],
      "transport": { "type": "httpupgrade", "path": "$HTTPUPGRADE_PATH" }
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "default_domain_resolver": "dns_remote",
    "rules": [
      { "inbound": "vless-in", "outbound": "warp-out" }
    ],
    "final": "direct"
  }
}
EOF

# ----- 启动 sing-box 服务 -----
info "重启 sing-box 服务..."
if systemctl is-active --quiet sing-box; then
    systemctl restart sing-box
else
    systemctl start sing-box
fi
systemctl enable sing-box

# ----- 安装 cloudflared -----
if ! command -v cloudflared &> /dev/null; then
    info "安装 cloudflared..."
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
fi

# ----- 启动 Argo 隧道 -----
info "启动 Argo 隧道..."
screen -ls | grep -q argo && screen -S argo -X quit
screen -dmS argo cloudflared tunnel --no-autoupdate run --token $ARGO_TOKEN
sleep 3
if screen -ls | grep -q argo; then
    info "Argo 隧道已启动"
else
    warn "Argo 隧道可能启动失败，请检查 Token 是否正确"
fi

# ----- 输出客户端信息 -----
echo ""
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}  蓝多依诺 VPS 一键部署完成！${NC}"
echo -e "${GREEN}===========================================${NC}"
echo "  协议: VLESS"
echo "  地址: $ARGO_DOMAIN"
echo "  端口: 443"
echo "  UUID: $VLESS_UUID"
echo "  传输: httpupgrade"
echo "  路径: $HTTPUPGRADE_PATH"
echo "  TLS: 由 Cloudflare CDN 提供"
echo "  SNI: $ARGO_DOMAIN"
echo ""
echo -e "${BLUE}分享链接:${NC}"
echo "vless://$VLESS_UUID@$ARGO_DOMAIN:443?type=tcp&security=tls&encryption=none&transport=httpupgrade&path=$(echo $HTTPUPGRADE_PATH | sed 's/\//%2F/g')&sni=$ARGO_DOMAIN"
echo ""
echo -e "${YELLOW}请确保已在 Cloudflare Zero Trust 面板中配置隧道:${NC}"
echo "  Domain: $ARGO_DOMAIN"
echo "  Service: HTTP → localhost:$LISTEN_PORT"
echo "  (路径可留空)"
echo ""
echo -e "${GREEN}享受高速安全上网！${NC}"
