#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

clear
echo "=========================================================="
echo "    欢迎使用 VLESS+Argo+WARP双出站 (v1.13+ 现代架构版)"
echo "=========================================================="
echo ""

# --- 1. 交互式获取用户参数 ---
read -p "请输入 Argo 隧道绑定的域名 (如 us3.989269.xyz): " ARGO_DOMAIN
read -p "请输入 Argo 隧道的 Token: " ARGO_TOKEN
read -p "请输入 Sing-box 监听端口 (直接回车默认设置为 8080): " USER_PORT
if [ -z "$USER_PORT" ]; then
    USER_PORT="8080"
    echo "已设置为默认端口: 8080"
fi
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

# --- 3. 申请专属 WARP 账号与密钥 (双重引擎防卡死) ---
echo ">> [2/5] 正在向 Cloudflare 申请专属 WARP 账号与密钥..."
mkdir -p /root/warp_temp && cd /root/warp_temp

sed -i '/api.cloudflareclient.com/d' /etc/hosts
echo "2606:4700::6812:7c60 api.cloudflareclient.com" >> /etc/hosts

wget -N https://github.moeyy.xyz/https://github.com/ViRb3/wgcf/releases/download/v2.2.22/wgcf_2.2.22_linux_amd64 -O /usr/local/bin/wgcf > /dev/null 2>&1
chmod +x /usr/local/bin/wgcf

timeout 20 wgcf register --accept-tos > /dev/null 2>&1
timeout 10 wgcf generate > /dev/null 2>&1

WARP_PRIV_KEY=$(grep "PrivateKey" wgcf-profile.conf 2>/dev/null | awk -F ' = ' '{print $2}')
WARP_IPV4=$(grep "Address" wgcf-profile.conf 2>/dev/null | head -n 1 | awk -F ' = ' '{print $2}')
WARP_IPV6=$(grep "Address" wgcf-profile.conf 2>/dev/null | tail -n 1 | awk -F ' = ' '{print $2}')

if [ -z "$WARP_PRIV_KEY" ]; then
    echo ">> wgcf 引擎申请超时，自动切换 warp-go 备用引擎..."
    wget -N https://github.moeyy.xyz/https://raw.githubusercontent.com/fscarmen/warp/main/warp-go/warp-go-linux-amd64 -O /usr/local/bin/warp-go > /dev/null 2>&1
    chmod +x /usr/local/bin/warp-go
    timeout 20 /usr/local/bin/warp-go --register --export-wireguard /root/warp_temp/warp.conf > /dev/null 2>&1
    
    WARP_PRIV_KEY=$(grep -oE "PrivateKey\s*=\s*[A-Za-z0-9+/=]+" /root/warp_temp/warp.conf 2>/dev/null | awk -F '=' '{print $2}' | tr -d ' ')
    WARP_IPV4=$(grep -oE "172\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+" /root/warp_temp/warp.conf 2>/dev/null)
    WARP_IPV6=$(grep -oE "2606:[a-f0-9:]+/[0-9]+" /root/warp_temp/warp.conf 2>/dev/null)
fi

sed -i '/api.cloudflareclient.com/d' /etc/hosts

if [ -z "$WARP_PRIV_KEY" ]; then
    echo "错误：WARP 账号申请彻底失败！当前网络环境极度受限。"
    exit 1
fi
echo ">> WARP 账号生成成功！"

# --- 4. 安装 Sing-box 最新内核 ---
echo ">> [3/5] 正在安装 Sing-box 官方最新原生内核..."
rm -rf /etc/sing-box/config.json 2>/dev/null
wget -qO sing-box.deb "https://github.moeyy.xyz/https://github.com/SagerNet/sing-box/releases/download/v1.13.12/sing-box_1.13.12_linux_amd64.deb"
dpkg -i sing-box.deb > /dev/null 2>&1
rm -f sing-box.deb

# --- 5. 生成 Sing-box 专属配置 (全新 v1.13+ Endpoint 与 DNS 语法) ---
echo ">> [4/5] 正在生成 Sing-box 专属配置 (现代化架构)..."
cat > /etc/sing-box/config.json << CONFIG_EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "type": "https",
        "tag": "dns_remote",
        "server": "1.1.1.1",
        "detour": "warp-out"
      },
      {
        "type": "udp",
        "tag": "dns_local",
        "server": "2606:4700:4700::1111",
        "detour": "direct"
      }
    ],
    "rules": [
      {
        "outbound": "any",
        "server": "dns_remote"
      }
    ]
  },
  "endpoints": [
    {
      "type": "wireguard",
      "tag": "warp-out",
      "system": false,
      "mtu": 1280,
      "address": [
        "${WARP_IPV4}",
        "${WARP_IPV6}"
      ],
      "private_key": "${WARP_PRIV_KEY}",
      "peers": [
        {
          "address": "2606:4700:d0::a29f:c001",
          "port": 2408,
          "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          "allowed_ips": [
            "0.0.0.0/0",
            "::/0"
          ],
          "reserved": [0,0,0]
        }
      ]
    }
  ],
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "127.0.0.1",
      "listen_port": ${USER_PORT},
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
      "type": "block",
      "tag": "block-out"
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "default_domain_resolver": "dns_local",
    "rules": [
      {
        "inbound": "vless-in",
        "outbound": "warp-out"
      }
    ],
    "final": "block-out"
  }
}
CONFIG_EOF

# 彻底清理之前所有的旧版环境变量残留补丁
rm -rf /etc/systemd/system/sing-box.service.d 2>/dev/null

systemctl daemon-reload
systemctl enable sing-box > /dev/null 2>&1
systemctl restart sing-box

# --- 6. 安装并启动 Argo 隧道 ---
echo ">> [5/5] 正在打通 Argo CDN 隧道..."
curl -L "https://github.moeyy.xyz/https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" -o /usr/local/bin/cloudflared > /dev/null 2>&1
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

rm -rf /root/warp_temp
