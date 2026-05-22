#!/bin/bash

# ====================================================
# HAX 纯 IPv6 专属：Sing-box + WARP + Argo 终极全自动闭环版
# 特性: 战前自动清场, 纯交互参数, 离线直装, 绝对 0 报错静默执行
# ====================================================

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

echo -e "${GREEN}=== HAX 纯 IPv6 专属极客部署 (洁癖打磨版) ===${RESET}"

# 1. 强制固化 NAT64/DNS64 网关
echo -e "\n${GREEN}[1/4] 正在固化 IPv4 访问能力并清理环境...${RESET}"
chattr -i /etc/resolv.conf 2>/dev/null || true
echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a01:4f8:c2c:123f::1" > /etc/resolv.conf
chattr +i /etc/resolv.conf 2>/dev/null || true

# 【核心修复1】清理上一版遗留的坏源，防止 apt update 中断
rm -f /etc/apt/sources.list.d/sagernet.list
sleep 1

# 2. 纯交互式获取参数
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
[[ "$VLESS_PATH" != /* ]] && VLESS_PATH="/$VLESS_PATH"

VLESS_UUID=$(cat /proc/sys/kernel/random/uuid)
echo -e "\n-> 本机随机生成 UUID: ${YELLOW}${VLESS_UUID}${RESET}"

# 3. 安装配置 Sing-box 服务端
echo -e "\n${GREEN}[3/4] 正在下载并直装 Sing-box 核心...${RESET}"
apt update -y && apt install -y curl wget jq
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    SB_ARCH="amd64"
elif [ "$ARCH" = "aarch64" ]; then
    SB_ARCH="arm64"
else
    echo -e "${RED}不支持的架构: $ARCH${RESET}"; exit 1
fi

# 抓取最新版 (不再报 jq 找不到的错误)
SB_VER=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | jq -r .tag_name | sed 's/v//')
if [ -z "$SB_VER" ] || [ "$SB_VER" = "null" ]; then
    SB_VER="1.9.3"
fi

wget -qO sing-box.deb "https://github.com/SagerNet/sing-box/releases/download/v${SB_VER}/sing-box_${SB_VER}_linux_${SB_ARCH}.deb"

# 【核心修复2】提前删除旧配置，防止 dpkg 弹出交互式询问卡死脚本
rm -f /etc/sing-box/config.json
dpkg -i sing-box.deb
rm -f sing-box.deb

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

# 4. 安装配置 Cloudflare Argo 隧道
echo -e "\n${GREEN}[4/4] 正在下载并重置 Cloudflare Argo 隧道...${RESET}"
if [ "$ARCH" = "x86_64" ]; then
    CF_ARCH="amd64"
elif [ "$ARCH" = "aarch64" ]; then
    CF_ARCH="arm64"
fi

wget -qO cloudflared.deb "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}.deb"
dpkg -i cloudflared.deb
rm -f cloudflared.deb

# 【核心修复3】提前卸载可能存在的旧服务，防止 Token 注入失败
cloudflared service uninstall 2>/dev/null || true
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
