#!/bin/sh
# VMess/VLESS + Argo 一键脚本
# 支持多系统 + NAT VPS 检测 + 双协议选择 + 守护进程 + 客户端配置生成

set -e

UUID=$(cat /proc/sys/kernel/random/uuid)
WS_PATH="/$(head -n 10 /dev/urandom | md5sum | cut -c1-8)"
OS=$(grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '"')

# 安装 v2ray
install_v2ray() {
  case "$OS" in
    alpine)
      apk update
      apk add --no-cache curl wget bash unzip v2ray
      ;;
    debian|ubuntu)
      apt update
      apt install -y curl wget unzip bash
      curl -L https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip -o v2ray.zip
      unzip v2ray.zip -d /usr/local/bin/
      ;;
    centos|fedora)
      yum install -y curl wget unzip bash
      curl -L https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip -o v2ray.zip
      unzip v2ray.zip -d /usr/local/bin/
      ;;
    *)
      echo "未知系统: $OS，请手动安装 v2ray"
      exit 1
      ;;
  esac
}

# 安装 cloudflared
install_cloudflared() {
  if ! command -v cloudflared >/dev/null; then
    wget -O /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
    chmod +x /usr/local/bin/cloudflared
  fi
}

install_v2ray
install_cloudflared

# NAT VPS 检测
PUBLIC_IP=$(curl -s ifconfig.me || echo "0.0.0.0")
LOCAL_IP=$(ip -4 addr show | grep inet | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | head -n1)

if [ "$PUBLIC_IP" = "$LOCAL_IP" ]; then
  NAT_MODE="false"
else
  NAT_MODE="true"
fi

if [ "$NAT_MODE" = "true" ]; then
  LISTEN_IP="127.0.0.1"
  LISTEN_PORT="8080"
else
  LISTEN_IP="0.0.0.0"
  LISTEN_PORT="443"
fi

# 协议选择
echo "请选择协议类型:"
echo "1) VMess"
echo "2) VLESS"
echo "3) VMess + VLESS"
read -p "输入选项 [1/2/3]: " PROTO

mkdir -p /etc/v2ray

if [ "$PROTO" = "1" ]; then
  # VMess 配置
  cat > /etc/v2ray/config.json <<EOF
{
  "inbounds": [
    {
      "port": $LISTEN_PORT,
      "listen": "$LISTEN_IP",
      "protocol": "vmess",
      "settings": {
        "clients": [
          { "id": "$UUID", "alterId": 0 }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "$WS_PATH-vmess" }
      }
    }
  ],
  "outbounds": [ { "protocol": "freedom" } ]
}
EOF
elif [ "$PROTO" = "2" ]; then
  # VLESS 配置
  cat > /etc/v2ray/config.json <<EOF
{
  "inbounds": [
    {
      "port": $LISTEN_PORT,
      "listen": "$LISTEN_IP",
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "$UUID" }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "$WS_PATH-vless" }
      }
    }
  ],
  "outbounds": [ { "protocol": "freedom" } ]
}
EOF
else
  # VMess + VLESS 双协议
  cat > /etc/v2ray/config.json <<EOF
{
  "inbounds": [
    {
      "port": $LISTEN_PORT,
      "listen": "$LISTEN_IP",
      "protocol": "vmess",
      "settings": {
        "clients": [
          { "id": "$UUID", "alterId": 0 }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "$WS_PATH-vmess" }
      }
    },
    {
      "port": $((LISTEN_PORT+1)),
      "listen": "$LISTEN_IP",
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "$UUID" }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "$WS_PATH-vless" }
      }
    }
  ],
  "outbounds": [ { "protocol": "freedom" } ]
}
EOF
fi

# 启动 v2ray
if [ "$OS" = "alpine" ]; then
  rc-update add v2ray default
  rc-service v2ray restart
else
  nohup v2ray run -c /etc/v2ray/config.json >/var/log/v2ray.log 2>&1 &
fi

# 伪装域名选择
echo "请选择伪装域名模式:"
echo "1) 使用 Argo 随机域名"
echo "2) 使用自定义域名"
read -p "输入选项 [1/2]: " MODE

if [ "$MODE" = "2" ]; then
  read -p "请输入你的伪装域名 (例如 example.com): " CUSTOM_DOMAIN
else
  CUSTOM_DOMAIN=""
fi

# 启动 cloudflared
cloudflared tunnel --no-autoupdate --metrics localhost:0 --protocol http2 --url http://127.0.0.1:$LISTEN_PORT > /var/log/cloudflared.log 2>&1 &

# 守护脚本
cat > /usr/local/bin/argo-guard.sh <<'GUARD'
#!/bin/sh
while true; do
  if ! pgrep -x v2ray >/dev/null; then
    echo "v2ray stopped, restarting..."
    rc-service v2ray restart || nohup v2ray run -c /etc/v2ray/config.json >/var/log/v2ray.log 2>&1 &
  fi
  if ! pgrep -x cloudflared >/dev/null; then
    echo "cloudflared stopped, restarting..."
    cloudflared tunnel --no-autoupdate --metrics localhost:0 --protocol http2 --url http://127.0.0.1:8080 > /var/log/cloudflared.log 2>&1 &
  fi
  sleep 30
done
GUARD

chmod +x /usr/local/bin/argo-guard.sh
nohup /usr/local/bin/argo-guard.sh >/var/log/argo-guard.log 2>&1 &

sleep 5
ARGO_DOMAIN=$(grep -oE "https://[a-z0-9-]+\.trycloudflare\.com" /var/log/cloudflared.log | tail -n1)

if [ -n "$CUSTOM_DOMAIN" ]; then
  FINAL_DOMAIN="$CUSTOM_DOMAIN"
else
  FINAL_DOMAIN=$(echo $ARGO_DOMAIN | sed 's#https://##')
fi

# 自动生成客户端配置文件
mkdir -p /root/clients

cat > /root/clients/clash-meta.yaml <<EOF
proxies:
  - name: vmess-argo
    type: vmess
    server: $FINAL_DOMAIN
    port: 443
    uuid: $UUID
    alterId: 0
    cipher: auto
    tls: true
    network: ws
    ws-opts:
      path: $WS_PATH-vmess
      headers:
        Host: $FINAL_DOMAIN

  - name: vless-argo
    type: vless
    server: $FINAL_DOMAIN
    port: 443
    uuid: $UUID
    tls: true
    network: ws
    udp: true
    ws-opts:
      path: $WS_PATH-vless
      headers:
        Host: $FINAL_DOMAIN
EOF

cat > /root/clients/v2rayng.json <<EOF
{
  "outbounds": [
    {
      "protocol": "vmess",
      "settings": {
