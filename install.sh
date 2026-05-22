#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

clear
echo "=========================================================="
echo "    欢迎使用 VLESS+Argo+WARP双出站(IPv6优先) 部署脚本"
echo "=========================================================="
echo ""

# --- 1. 交互式获取用户参数 ---
read -p "请输入 Argo 隧道绑定的域名 (如 us3.989269.xyz): " ARGO_DOMAIN
read -p "请输入 Argo 隧道的 Token: " ARGO_TOKEN
read -p "请输入自定义 UUID (直接回车将自动生成一个): " USER_UUID
if [ -z "$USER_UUID" ]; then
    USER_UUID=$(cat /proc/sys/kernel/random/uuid)
    echo "已自动生成 UUID: $USER_UUID"
fi
read -p "请输入路径 (直接回车将默认设置为 /mysecretpath): " USER_PATH
if [ -z "$USER_PATH" ]; then
    USER_PATH="/mysecretpath"
    echo "已设置为默认路径: $USER_PATH"
fi
echo ""
echo "=========================================================="
echo "参数收集完毕，开始全自动部署，请耐心等待..."
echo "=========================================================="

# --- 2. 安装必备系统组件 ---
echo ">> [1/5] 正在安装系统基础组件..."
apt update -y > /dev/null 2>&1
apt install -y curl wget jq qrencode screen > /dev/null 2>&1

# --- 3. 申请专属 WARP 账号与密钥 (带防卡死与双重保险机制) ---
echo ">> [2/5] 正在向 Cloudflare 申请专属 WARP 账号与密钥..."
mkdir -p /root/warp_temp && cd /root/warp_temp

# 【核心黑科技】强制让 Cloudflare API 走干净的原生 IPv6，绕过被墙的 NAT64
sed -i '/api.cloudflareclient.com/d' /etc/hosts
echo "2606:4700::6812:7c60 api.cloudflareclient.com" >> /etc/hosts

wget -N https://github.com/ViRb3/wgcf/releases/download/v2.2.22/wgcf_2.2.22_linux_amd64 -O /usr/local/bin/wgcf > /dev/null 2>&1
chmod +x /usr/local/bin/wgcf

# 使用 timeout 超时退出，并使用官方参数自动同意协议，杜绝管道卡死
timeout 20 wgcf register --accept-tos > /dev/null 2>&1
timeout 10 wgcf generate > /dev/null 2>&1

WARP_PRIV_KEY=$(grep "PrivateKey" wgcf-profile.conf 2>/dev/null | awk -F ' = ' '{print $2}')
WARP_IPV4=$(grep "Address" wgcf-profile.conf 2>/dev/null | head -n 1 | awk -F ' = ' '{print $2}')
WARP_IPV6=$(grep "Address" wgcf-profile.conf 2>/dev/null | tail -n 1 | awk -F ' = ' '{print $2}')

# 【备用方案】如果 wgcf 引擎失败，自动切换至 warp-go 引擎进行申请
if [ -z "$WARP_PRIV_KEY" ]; then
    echo ">> wgcf 引擎申请超时，正在自动切换至 warp-go 备用引擎重试..."
    wget -N https://raw.githubusercontent.com/fscarmen/warp/main/warp-go/warp-go-linux-amd64 -O /usr/local/bin/warp-go > /dev/null 2>&1
    chmod +x /usr/local/bin/warp-go
    timeout 20 /usr/local/bin/warp-go --register --export-wireguard /root/warp_temp/warp.conf > /dev/null 2>&1
    
    WARP_PRIV_KEY=$(grep -oE "PrivateKey\s*=\s*[A-Za-z0-9+/=]+" /root/warp_temp/warp.conf 2>/dev/null | awk -F '=' '{print $2}' | tr -d ' ')
    WARP_IPV4=$(grep -oE "172\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+" /root/warp_temp/warp.conf 2>/dev/null)
    WARP_IPV6=$(grep -oE "2606:[a-f0-9:]+/[0-9]+" /root/warp_temp/warp.conf 2>/dev/null)
fi

if [ -z "$WARP_PRIV_KEY" ]; then
    echo "错误：WARP 账号自动生成彻底失败。当前 VPS 的网络环境极其受限。"
    exit 1
fi
echo ">> WARP 账号生成成功！(已获取双栈 IP 及私钥)"

# 恢复 hosts，不影响系统后续运行
sed -i '/api.cloudflareclient.com/d' /etc/hosts

# --- 4. 安装 Sing-box 内核 ---
echo ">> [3/5] 正在安装 Sing-box 官方原生内核..."
rm -rf /etc/sing-box/config.json 2>/dev/null
curl -fsSL https://sing-box.app/install.sh | bash

# --- 5. 生成 Sing-box 专属配置 (内置 VLESS+WARP双栈+防泄漏) ---
echo ">> [4/5] 正在生成 Sing-box 专属配置..."
cat > /etc/sing-box/config.json << CONFIG_EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "127.0.0.1",
      "listen_port": 8080,
      "users": [
        {
          "uuid": "${USER_UUID}",
          "flow": ""
        }
      ],
      "transport": {
        "type": "httpupgrade",
        "path": "${USER_PATH}"
      }
    }
  ],
  "outbounds": [
    {
      "type": "wireguard",
      "tag": "warp-out",
      "server": "2606:4700:d0::a29f:c001",
      "server_port": 2408,
      "local_address": [
        "${WARP_IPV4}",
        "${WARP_IPV6}"
      ],
      "private_key": "${WARP_PRIV_KEY}",
      "peer_public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
      "reserved": [0,0,0],
      "mtu": 1280
    },
    {
      "type": "block",
      "tag": "block-out"
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [
      {
        "inbound": "vless-in",
        "outbound": "warp-out"
      }
    ],
    "default_domain_resolver": "dns_remote",
    "final": "block-out"
  },
  "dns": {
    "servers": [
      {
        "tag": "dns_remote",
        "address": "https://1.1.1.1/dns-query",
        "address_resolver": "dns_local",
        "strategy": "prefer_ipv6",
        "detour": "warp-out"
      },
      {
        "tag": "dns_local",
        "address": "2606:4700:4700::1111",
        "detour": "direct"
      }
    ],
    "rules": [
      {
        "outbound": "any",
        "server": "dns_remote"
      }
    ]
  }
}
CONFIG_EOF

systemctl daemon-reload
systemctl enable sing-box > /dev/null 2>&1
systemctl restart sing-box

# --- 6. 安装并启动 Argo 隧道 ---
echo ">> [5/5] 正在打通 Argo CDN 隧道..."
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared > /dev/null 2>&1
chmod +x /usr/local/bin/cloudflared
screen -S argo -X quit 2>/dev/null
screen -dmS argo cloudflared tunnel --no-autoupdate run --token ${ARGO_TOKEN}

# --- 7. 生成 V2rayN 分享链接 ---
VLESS_LINK="vless://${USER_UUID}@${ARGO_DOMAIN}:443?encryption=none&security=tls&type=httpupgrade&path=${USER_PATH//\//%2F}#WARP-DualStack-IPv6First"

echo ""
echo "=========================================================="
echo "                   🎉 部署大功告成！ 🎉                   "
echo "=========================================================="
echo "V2rayN 一键导入链接："
echo -e "\033[32m${VLESS_LINK}\033[0m"
echo "=========================================================="

# 运行完毕清理临时文件
rm -rf /root/warp_temp
