#!/bin/bash

# ====================================================
# HAX 纯 IPv6 专属：Sing-box + WARP 原生双栈部署 (交互防阻断版)
# 特性: 强制固化 NAT64, 纯手动填入 WARP 参数，100% 成功率无报错
# ====================================================

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

echo -e "${GREEN}=== 启动 HAX 纯 IPv6 专属极客部署 (交互版) ===${RESET}"

# 1. 强制固化 NAT64/DNS64 网关 (纯6机器破冰必备)
echo -e "\n${GREEN}[1/3] 正在配置 NAT64/DNS64 网关...${RESET}"
# 解除可能存在的锁定
chattr -i /etc/resolv.conf 2>/dev/null || true
echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a01:4f8:c2c:123f::1" > /etc/resolv.conf
# 重新锁定防止系统重启覆盖
chattr +i /etc/resolv.conf 2>/dev/null || true
sleep 1

# 2. 交互式录入核心参数
echo -e "\n${GREEN}[2/3] 请粘贴你从网页 (LANRAT) 或本地获取的 WARP 节点参数：${RESET}"
read -p "1. 输入 WARP PrivateKey (私钥): " WARP_PK
read -p "2. 输入 WARP IPv6 (如 2606:4700... 注意末尾不要带 /128): " WARP_IPV6
read -p "3. 输入 Reserved (包含方括号，直接回车默认 [0,0,0]): " WARP_RESERVED
WARP_RESERVED=${WARP_RESERVED:-"[0,0,0]"}

VLESS_PORT=60001
VLESS_UUID=$(cat /proc/sys/kernel/random/uuid)
VLESS_PATH="/wolovelangduo520"

echo -e "\n-> 分配 VLESS 端口: ${YELLOW}${VLESS_PORT}${RESET}"
echo -e "-> 生成 VLESS UUID: ${YELLOW}${VLESS_UUID}${RESET}"

# 3. 安装官方原版 Sing-box
echo -e "\n${GREEN}[3/3] 正在安装 Sing-box 并写入原生直连配置...${RESET}"
apt update -y && apt install -y curl gnupg2 ca-certificates
curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
chmod a+r /etc/apt/keyrings/sagernet.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/sagernet.asc] https://deb.sagernet.org/ * *" | tee /etc/apt/sources.list.d/sagernet.list > /dev/null
apt update -y && apt install -y sing-box

# 4. 写入原生 WireGuard 终极配置
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

echo "------------------------------------------------"
echo -e "${GREEN}🎉 交互式部署大功告成！原生双栈节点已起飞！${RESET}"
echo "------------------------------------------------"
echo -e "你的 VLESS 连接信息如下："
echo -e "端口:    ${YELLOW}443${RESET} (Argo 入口)"
echo -e "UUID:    ${YELLOW}${VLESS_UUID}${RESET}"
echo -e "路径:    ${YELLOW}${VLESS_PATH}${RESET}"
echo -e "TLS:     ${YELLOW}开启 (填入你的 Argo 域名作为 SNI)${RESET}"
echo "------------------------------------------------"
echo -e "⚠️ 请务必去 Cloudflare 隧道面板将端口指向: ${YELLOW}localhost:${VLESS_PORT}${RESET}"
