#!/bin/bash

# ====================================================
# HAX 纯 IPv6 专属：Sing-box + WARP 原生双栈（Argo 交互与分享链接版）
# 特性: 固化 NAT64, 纯手动填入 WARP 参数, 自动生成 VLESS 一键导入链接
# ====================================================

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

echo -e "${GREEN}=== 启动 HAX 纯 IPv6 专属极客部署 (Argo+链接版) ===${RESET}"

# 1. 强制固化 NAT64/DNS64 网关 (纯6机器破冰必备)
echo -e "\n${GREEN}[1/3] 正在配置 NAT64/DNS64 网关...${RESET}"
chattr -i /etc/resolv.conf 2>/dev/null || true
echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a01:4f8:c2c:123f::1" > /etc/resolv.conf
chattr +i /etc/resolv.conf 2>/dev/null || true
sleep 1

# 2. 交互式录入核心参数
echo -e "\n${GREEN}[2/3] 请输入你的节点配置参数：${RESET}"
read -p "1. 输入 WARP PrivateKey (私钥): " WARP_PK
read -p "2. 输入 WARP IPv6 (如 2606:4700... 注意末尾不要带 /128): " WARP_IPV6
read -p "3. 输入 Reserved (包含方跨号，直接回车默认 [0,0,0]): " WARP_RESERVED
WARP_RESERVED=${WARP_RESERVED:-"[0,0,0]"}
read -p "4. 输入你的 Argo 域名 (如 xxx.trycloudflare.com): " ARGO_DOMAIN

# 自动生成内部参数
VLESS_PORT=60001
VLESS_UUID=$(cat /proc/sys/kernel/random/uuid)
VLESS_PATH="/wolovelangduo520"

echo -e "\n-> 内部端口分配: ${YELLOW}${VLESS_PORT}${RESET}"
echo -e "-> 自动生成 UUID: ${YELLOW}${VLESS_UUID}${RESET}"

# 3. 安装官方原版 Sing-box
echo -e "\n${GREEN}[3/3] 正在安装 Sing-box 并写入原生直连配置...${RESET}"
apt update -y && apt install -y curl gnupg2 ca-certificates
curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
chmod a+r /etc/apt/keyrings/sagernet.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/sagernet.asc] https://deb.sagernet.org/ * *" | tee /etc/apt/sources.list.d/sagernet.list > /dev/null
apt update -y && apt install -y sing-box

# 4. 写入原生 WireGuard 配置文件
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

# 5. 启动服务
systemctl enable --now sing-box
systemctl restart sing-box

# 6. 【核心升级】对路径进行 URL 编码并组装标准 VLESS 分享链接
VLESS_PATH_ENC=$(echo -n "${VLESS_PATH}" | sed 's/\//%2F/g')
VLESS_LINK="vless://${VLESS_UUID}@${ARGO_DOMAIN}:443?encryption=none&security=tls&sni=${ARGO_DOMAIN}&type=httpupgrade&path=${VLESS_PATH_ENC}#HAX_Singbox_WARP"

echo "------------------------------------------------"
echo -e "${GREEN}🎉 交互式部署大功告成！节点已无缝对接 Argo 隧道！${RESET}"
echo "------------------------------------------------"
echo -e "${GREEN}👇 请复制下方生成的 VLESS 一键导入链接 👇${RESET}"
echo -e "${YELLOW}${VLESS_LINK}${RESET}"
echo "------------------------------------------------"
echo -e "⚠️  提示: 你的 Cloudflare 隧道面板请将端口指向: ${YELLOW}localhost:${VLESS_PORT}${RESET}"
echo "------------------------------------------------"
