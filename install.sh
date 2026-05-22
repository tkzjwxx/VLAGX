#!/bin/bash

# ====================================================
# HAX 纯 IPv6 专属：Sing-box + WARP + Argo 终极全自动闭环版
# 特性: 强制固化 NAT64, 纯交互式参数录入, 强制 IPv4 绕过残缺路由
# ====================================================

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

echo -e "${GREEN}=== HAX 纯 IPv6 专属极客部署 (终极强杀 ALL IN ONE) ===${RESET}"

# 1. 强制固化 NAT64/DNS64 网关 (纯6机器破冰)
echo -e "\n${GREEN}[1/4] 正在固化 IPv4 访问能力...${RESET}"
chattr -i /etc/resolv.conf 2>/dev/null || true
echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a01:4f8:c2c:123f::1" > /etc/resolv.conf
chattr +i /etc/resolv.conf 2>/dev/null || true
sleep 1

# 2. 纯交互式获取所有参数 (绝对不强制指定)
echo -e "\n${GREEN}[2/4] 请输入你的专属节点参数：${RESET}"
echo -e "${YELLOW}--- WARP 拨号配置 ---${RESET}"
read -p "1. WARP PrivateKey (私钥): " WARP_PK
read -p "2. WARP IPv6 (如 2606:4700... 不带 /128): " WARP_IPV6
read -p "3. Reserved (含方括号，回车默认 [0,0,0]): " WARP_RESERVED
WARP_RESERVED=${WARP_RESERVED:-"[0,0,0]"}

echo -e "\n${YELLOW}--- Argo 隧道配置 ---${RESET}"
read -p "4. Argo Tunnel Token: " ARGO_TOKEN
read -p "5. 绑定的 Argo 域名 (如 a.abc.com): " ARGO_DOMAIN

echo -e "\n${YELLOW}--- Sing-box 节点配置 ---${RESET}"
read -p "6. 设置本地监听端口 (如 60001): " VLESS_PORT
read -p "7. 设置 WebSocket 路径 (如 /wolovelangduo520): " VLESS_PATH
# 确保路径以 / 开头
[[ "$VLESS_PATH" != /* ]] && VLESS_PATH="/$VLESS_PATH"

VLESS_UUID=$(cat /proc/sys/kernel/random/uuid)
echo -e "\n-> 本机随机生成 UUID: ${YELLOW}${VLESS_UUID}${RESET}"

# 3. 安装配置 Sing-box 服务端 (强制走 IPv4 隧道规避超时)
echo -e "\n${GREEN}[3/4] 正在强制通过 NAT64 安装 Sing-box...${RESET}"
apt -o Acquire::ForceIPv4=true update -y && apt -o Acquire::ForceIPv4=true install -y curl gnupg2 ca-certificates wget
curl -4 -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
chmod a+r /etc/apt/keyrings/sagernet.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/sagernet.asc] https://deb.sagernet.org/ * *" | tee /etc/apt/sources.list.d/sagernet.list > /dev/null
apt -o Acquire::ForceIPv4=true update -y && apt -o Acquire::ForceIPv4=true install -y sing-box

mkdir -p /etc/sing-box
cat << EOF > /etc/sing-box/config.json
{
  "log": { "level": "info" },
  "dns": {
    "servers": [
      { "tag": "dns_direct", "type": "udp", "server": "2606:4700:4700::1111" }
    ],
    "strategy": "prefer_ipv6"
  },
  "endpoints": [
    {
      "type": "wireguard",
      "tag": "warp-out",
      "address": [ "172.16.0.2/32", "${WARP_IPV6}/128" ],
      "private_key": "${WARP_PK}",
      "peers": [
        {
          "address": "2606:4700:d0::a29f:c001",
          "port": 2408,
          "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          "reserved": ${WARP_RESERVED},
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
      "listen_port": ${VLESS_PORT},
      "users": [{ "uuid": "${VLESS_UUID}" }],
      "transport": { "type": "httpupgrade", "path": "${VLESS_PATH}" }
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "rules": [
      { "inbound": "vless-in", "outbound": "warp-out" }
    ],
    "final": "direct"
  }
}
EOF

systemctl enable --now sing-box
systemctl restart sing-box

# 4. 安装配置 Cloudflare Argo 隧道 (强制走 IPv4 规避超时)
echo -e "\n${GREEN}[4/4] 正在安装并注册 Cloudflare Argo 隧道...${RESET}"
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
elif [ "$ARCH" = "aarch64" ]; then
    URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb"
else
    echo -e "${RED}不支持的架构: $ARCH${RESET}"
    exit 1
fi

wget -4 -qO cloudflared.deb "$URL"
dpkg -i cloudflared.deb
rm -f cloudflared.deb

cloudflared service install "${ARGO_TOKEN}"
systemctl start cloudflared
systemctl enable cloudflared

# 5. 生成客户端 VLESS 链接
VLESS_PATH_ENC=$(echo -n "${VLESS_PATH}" | sed 's/\//%2F/g')
VLESS_LINK="vless://${VLESS_UUID}@${ARGO_DOMAIN}:443?encryption=none&security=tls&sni=${ARGO_DOMAIN}&type=httpupgrade&path=${VLESS_PATH_ENC}#HAX_Singbox"

echo -e "\n========================================================="
echo -e "${GREEN}🎉 ALL IN ONE 部署完成！Sing-box 与 Argo 隧道均已拉起！${RESET}"
echo -e "========================================================="
echo -e "${GREEN}👇 你的专属 VLESS 一键导入链接 👇${RESET}"
echo -e "${YELLOW}${VLESS_LINK}${RESET}"
echo -e "========================================================="
echo -e "⚠️ 【最后一步】请前往 Cloudflare Zero Trust 控制台："
echo -e "确保你的 Tunnels -> Public Hostname 流量转发目标设置为："
echo -e "👉  ${YELLOW}http://localhost:${VLESS_PORT}${RESET}"
echo -e "========================================================="
