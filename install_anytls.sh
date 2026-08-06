#!/bin/bash

# 设置颜色变量
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
PLAIN="\033[0m"

# 默认变量值
DOMAIN=""
PORT=443
SOCKS_PORT=1080

# 1. 接收命令行参数 (例如: bash install_anytls.sh -d example.com -p 8443)
while getopts "d:p:s:" opt; do
  case $opt in
    d) DOMAIN="$OPTARG" ;;
    p) PORT="$OPTARG" ;;
    s) SOCKS_PORT="$OPTARG" ;;
    *) ;;
  esac
done

echo -e "${GREEN}[+] 开始部署 Sing-box AnyTLS + Socks5 服务...${PLAIN}"

# 2. 检查并安装基础依赖与 Sing-box 核心
echo -e "${BLUE}[*] 正在检查依赖环境及安装最新的 Sing-box 核心...${PLAIN}"
if command -v apt-get &>/dev/null; then
    apt-get update -y && apt-get install -y curl socat cron tar jq &>/dev/null
elif command -v yum &>/dev/null; then
    yum install -y curl socat crontabs tar jq &>/dev/null
fi

# 安装支持 AnyTLS 的 Sing-box 预发/最新版 (--prerelease)
bash <(curl -fsSL https://sing-box.app/deb-install.sh) --prerelease

# 3. 交互式获取参数 (如果命令行未传入 -d 参数)
if [ -z "$DOMAIN" ]; then
    read -p "请输入解析到本机 IP 的域名 (必须): " DOMAIN
fi

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}[-] 错误：必须提供有效域名！部署终止。${PLAIN}"
    exit 1
fi

# 生成随机密码与账号
ANYTLS_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
SOCKS_USER="user_$(head /dev/urandom | tr -dc 0-9 | head -c 4)"
SOCKS_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)

# 4. 使用 acme.sh 自动申请 TLS 证书
echo -e "${BLUE}[*] 正在检查/申请 TLS 证书...${PLAIN}"
CERT_DIR="/etc/sing-box/cert"
mkdir -p "${CERT_DIR}"
CERT_PATH="${CERT_DIR}/${DOMAIN}.crt"
KEY_PATH="${CERT_DIR}/${DOMAIN}.key"

if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
    # 尝试临时释放 80 端口
    systemctl stop nginx &>/dev/null
    systemctl stop apache2 &>/dev/null

    # 安装 acme.sh 并申请证书
    curl https://get.acme.sh | sh -s email=admin@${DOMAIN} &>/dev/null
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade &>/dev/null
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d "${DOMAIN}" --standalone -k ec-256

    # 安装证书到 sing-box 目录
    ~/.acme.sh/acme.sh --install-cert -d "${DOMAIN}" --ecc \
        --fullchain-file "${CERT_PATH}" \
        --key-file "${KEY_PATH}"
fi

if [ ! -f "$CERT_PATH" ]; then
    echo -e "${RED}[-] 错误：TLS 证书申请失败！请确认域名解析正确且 80 端口无防火墙阻拦。${PLAIN}"
    exit 1
fi

# 5. 写入 Sing-box 配置文件
echo -e "${BLUE}[*] 正在生成配置文件...${PLAIN}"
mkdir -p /etc/sing-box/

cat <<EOF > /etc/sing-box/config.json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": ${PORT},
      "users": [
        {
          "name": "default_user",
          "password": "${ANYTLS_PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${DOMAIN}",
        "certificate_path": "${CERT_PATH}",
        "key_path": "${KEY_PATH}"
      },
      "detour": "web-fallback"
    },
    {
      "type": "direct",
      "tag": "web-fallback",
      "listen": "127.0.0.1",
      "listen_port": 10080,
      "override_address": "bing.com",
      "override_port": 443
    },
    {
      "type": "socks",
      "tag": "socks-in",
      "listen": "::",
      "listen_port": ${SOCKS_PORT},
      "users": [
        {
          "username": "${SOCKS_USER}",
          "password": "${SOCKS_PASS}"
        }
      ]
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

# 6. 验证并启动服务
sing-box check -c /etc/sing-box/config.json
if [ $? -ne 0 ]; then
    echo -e "${RED}[-] 配置文件校验错误，启动失败！${PLAIN}"
    exit 1
fi

systemctl restart sing-box
systemctl enable sing-box &>/dev/null

# 7. 打印安装结果
echo -e "${GREEN}====================================================${PLAIN}"
echo -e "${GREEN}       Sing-box AnyTLS + Socks5 部署成功！          ${PLAIN}"
echo -e "${GREEN}====================================================${PLAIN}"
echo -e "${YELLOW}[ AnyTLS 节点配置 (防封防护项) ]${PLAIN}"
echo -e "  服务端地址 (Address) : ${DOMAIN}"
echo -e "  端口 (Port)           : ${PORT}"
echo -e "  密码 (Password)       : ${ANYTLS_PASSWORD}"
echo -e "  伪装域名 (SNI)        : ${DOMAIN}"
echo -e "----------------------------------------------------"
echo -e "${YELLOW}[ Socks5 节点配置 (带明文认证) ]${PLAIN}"
echo -e "  服务器地址 (IP/Domain): ${DOMAIN}"
echo -e "  端口 (Port)           : ${SOCKS_PORT}"
echo -e "  用户名 (User)         : ${SOCKS_USER}"
echo -e "  密码 (Password)       : ${SOCKS_PASS}"
echo -e "${GREEN}====================================================${PLAIN}"
