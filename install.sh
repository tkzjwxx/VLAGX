#!/bin/bash

# ====================================================
# HAX 纯 IPv6 专属：Sing-box + WARP 全自动直连一键起飞脚本
# 特性: 强制 NAT64, 官方 GitLab 直连下载, 完美规避 404
# ====================================================

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

echo -e "${GREEN}=== 启动 HAX 纯 IPv6 专属极客部署 (GitLab 破冰版) ===${RESET}"

# 1. 强制固化 NAT64/DNS64 网关
echo -e "\n${GREEN}[1/4] 正在配置 NAT64/DNS64 网关...${RESET}"
echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a01:4f8:c2c:123f::1" > /etc/resolv.conf
chattr +i /etc/resolv.conf 2>/dev/null || true
sleep 2

# 2. 生成节点基础参数
VLESS_PORT=60001
VLESS_UUID=$(cat /proc/sys/kernel/random/uuid)
VLESS_PATH="/wolovelangduo520"

echo -e "-> 分配 VLESS 端口: ${YELLOW}${VLESS_PORT}${RESET}"
echo -e "-> 生成 VLESS UUID: ${YELLOW}${VLESS_UUID}${RESET}"

# 3. 安装依赖并判断架构
echo -e "\n${GREEN}[2/4] 正在准备依赖与环境...${RESET}"
apt update -y && apt install -y wget curl jq tar
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) W_ARCH="amd64" ;;
    aarch64) W_ARCH="arm64" ;;
    *) echo -e "${RED}不支持的 CPU 架构!${RESET}"; exit 1 ;;
esac

# 4. 【核心修复】从官方 GitLab 仓库直连拉取发号引擎
echo -e "\n${GREEN}[3/4] 正在从官方 GitLab 源获取发号引擎...${RESET}"
GITLAB_URL="https://gitlab.com/fscarmen/warp/-/raw/main/warp-go/warp-go_1.0.8_linux_${W_ARCH}.tar.gz"

wget -qO warp-go.tar.gz "${GITLAB_URL}"

# 校验下载文件是否为合法的压缩包
if ! tar -tzf warp-go.tar.gz >/dev/null 2>&1; then
    echo -e "${RED}文件拉取失败！GitLab 拒绝了连接，请检查网关。${RESET}"
    rm -f warp-go.tar.gz
    exit 1
fi

echo -e "-> ${GREEN}成功突破网络限制，文件下载完整！${RESET}"
tar -xzf warp-go.tar.gz warp-go
chmod +x warp-go

# 自动向 Cloudflare 申请全新账号
echo -e "\n正在向 Cloudflare 申请专属 WARP 参数..."
./warp-go --register --export warp.conf >/dev/null 2>&1

if [ ! -f "warp.conf" ]; then
    echo -e "${RED}WARP 账号申请失败，可能是 CF 限制了当前 IP。${RESET}"
    rm -f warp-go warp-go.tar.gz
    exit 1
fi

# 精准提取参数
WARP_PK=$(grep 'PrivateKey' warp.conf | awk '{print $3}')
WARP_IPV6=$(grep 'Address' warp.conf | grep -oE '2606:[0-9a-fA-F:]+/128' | head -n 1)
WARP_RESERVED=$(grep 'Reserved' warp.conf | awk -F '=' '{print $2}' | tr -d ' ')
WARP_RESERVED=${WARP_RESERVED:-"[0,0,0]"}

echo -e "-> 私钥提取: ${YELLOW}成功 (隐藏显示)${RESET}"
echo -e "-> IPv6提取: ${YELLOW}${WARP_IPV6}${RESET}"
echo -e "-> 暗号提取: ${YELLOW}${WARP_RESERVED}${RESET}"

# 5. 安装官方原版 Sing-box
echo -e "\n${GREEN}[4/4] 正在安装 Sing-box 并写入原生直连配置...${RESET}"
curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
chmod a+r /etc/apt/keyrings/sagernet.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/sagernet.asc] https://deb.sagernet.org/ * *" | tee /etc/apt/sources.list.d/sagernet.list > /dev/null
apt update -y && apt install -y sing-box

# 6. 生成配置文件
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
      "address": [ "172.16.0.2/32", "${WARP_IPV6}" ],
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

# 7. 阅后即焚与启动
rm -f warp-go warp-go.tar.gz warp.conf
systemctl enable --now sing-box
systemctl restart sing-box

echo "------------------------------------------------"
echo -e "${GREEN}🎉 部署大功告成！全自动双栈节点已起飞！${RESET}"
echo "------------------------------------------------"
echo -e "你的 VLESS 连接信息如下："
echo -e "端口:    ${YELLOW}443${RESET} (Argo 入口)"
echo -e "UUID:    ${YELLOW}${VLESS_UUID}${RESET}"
echo -e "路径:    ${YELLOW}${VLESS_PATH}${RESET}"
echo -e "TLS:     ${YELLOW}开启 (填入你的 Argo 域名作为 SNI)${RESET}"
echo "------------------------------------------------"
echo -e "⚠️ 请记得去 Cloudflare 隧道面板将端口指向: ${YELLOW}localhost:${VLESS_PORT}${RESET}"
