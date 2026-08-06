#!/bin/bash

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
PLAIN="\033[0m"

DOMAIN=""
PORT=443
SOCKS_PORT=1080

# 1. 接收命令行参数
while getopts "d:p:s:" opt; do
  case $opt in
    d) DOMAIN="$OPTARG" ;;
    p) PORT="$OPTARG" ;;
    s) SOCKS_PORT="$OPTARG" ;;
    *) ;;
  esac
done

echo -e "${YELLOW}[*] 正在检查并清理旧的 Sing-box 部署环境...${PLAIN}"

# 停止并清理旧服务
systemctl stop sing-box &>/dev/null
systemctl disable sing-box &>/dev/null
rm -rf /etc/sing-box /var/lib/sing-box /usr/local/bin/info /usr/local/bin/anytls

echo -e "${GREEN}[+] 环境清理完成，开始重新部署 Sing-box AnyTLS + Socks5 服务...${PLAIN}"

# 2. 检查并获取域名（若未通过参数传入，则提示手动输入）
if [ -z "$DOMAIN" ] || [ "$DOMAIN" == "yourdomain.com" ]; then
    echo -e "${YELLOW}[!] 未检测到有效域名参数，请输入手动配置：${PLAIN}"
    read -p "请输入解析到本机 IP 的域名 (必须): " DOMAIN
fi

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}[-] 错误：未提供有效域名，部署终止！${PLAIN}"
    exit 1
fi

# 3. 安装依赖与 Sing-box
echo -e "${BLUE}[*] 正在检查依赖环境及安装最新的 Sing-box 核心...${PLAIN}"
if command -v apt-get &>/dev/null; then
    apt-get update -y && apt-get install -y curl socat cron tar jq &>/dev/null
elif command -v yum &>/dev/null; then
    yum install -y curl socat crontabs tar jq &>/dev/null
fi

bash <(curl -fsSL https://sing-box.app/deb-install.sh) --prerelease

# 生成随机账号密码
ANYTLS_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
SOCKS_USER="user_$(head /dev/urandom | tr -dc 0-9 | head -c 4)"
SOCKS_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)

# 4. 自动申请 TLS 证书
echo -e "${BLUE}[*] 正在申请/更新 TLS 证书 (域名: ${DOMAIN})...${PLAIN}"
CERT_DIR="/etc/sing-box/cert"
mkdir -p "${CERT_DIR}"
CERT_PATH="${CERT_DIR}/${DOMAIN}.crt"
KEY_PATH="${CERT_DIR}/${DOMAIN}.key"

# 停止占用 80 端口的服务
systemctl stop nginx &>/dev/null
systemctl stop apache2 &>/dev/null

curl https://get.acme.sh | sh -s email=admin@${DOMAIN} &>/dev/null
~/.acme.sh/acme.sh --upgrade --auto-upgrade &>/dev/null
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh --issue -d "${DOMAIN}" --standalone -k ec-256 --force

~/.acme.sh/acme.sh --install-cert -d "${DOMAIN}" --ecc \
    --fullchain-file "${CERT_PATH}" \
    --key-file "${KEY_PATH}"

# 5. 校验证书是否存在且非空
if [ ! -s "$CERT_PATH" ] || [ ! -s "$KEY_PATH" ]; then
    echo -e "${RED}[-] 错误：TLS 证书生成失败！${PLAIN}"
    echo -e "${YELLOW}[!] 请确认：${PLAIN}"
    echo -e "    1. 域名 [ ${DOMAIN} ] 已正确 A 记录解析到本机 IP"
    echo -e "    2. 本机防火墙已放行 80 端口"
    exit 1
fi

# 6. 生成配置文件
echo -e "${BLUE}[*] 正在配置 Sing-box 服务...${PLAIN}"
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

# 7. 校验并启动服务
sing-box check -c /etc/sing-box/config.json
if [ $? -ne 0 ]; then
    echo -e "${RED}[-] 配置文件校验失败！${PLAIN}"
    exit 1
fi

systemctl restart sing-box
systemctl enable sing-box &>/dev/null

# 8. 节点命名规则优化（提取二级域名 + 国旗 Flag）
SUB_DOMAIN=$(echo "${DOMAIN}" | cut -d'.' -f1)

FLAG="🌐"
LOWER_SUB=$(echo "${SUB_DOMAIN}" | tr '[:upper:]' '[:lower:]')
case "${LOWER_SUB}" in
    us*) FLAG="🇺🇸" ;;
    hk*) FLAG="🇭🇰" ;;
    jp*) FLAG="🇯🇵" ;;
    sg*) FLAG="🇸🇬" ;;
    tw*) FLAG="🇹🇼" ;;
    kr*) FLAG="🇰🇷" ;;
    uk*|gb*) FLAG="🇬🇧" ;;
    de*) FLAG="🇩🇪" ;;
    fr*) FLAG="🇫🇷" ;;
    ca*) FLAG="🇨🇦" ;;
    au*) FLAG="🇦🇺" ;;
    ru*) FLAG="🇷🇺" ;;
esac

NODE_NAME="${FLAG}${SUB_DOMAIN}"
ENCODED_NODE_NAME=$(echo -n "${NODE_NAME}" | jq -sRr @uri)

# 生成一键导入链接
SOCKS5_USER_PASS_B64=$(echo -n "${SOCKS_USER}:${SOCKS_PASS}" | base64 -w 0)
SOCKS5_URL="socks://${SOCKS5_USER_PASS_B64}@${DOMAIN}:${SOCKS_PORT}#${ENCODED_NODE_NAME}"
ANYTLS_URL="anytls://${ANYTLS_PASSWORD}@${DOMAIN}:${PORT}?peer=${DOMAIN}&sni=${DOMAIN}#${ENCODED_NODE_NAME}"

CLIENT_JSON=$(cat <<EOF
{
  "type": "anytls",
  "tag": "${NODE_NAME}",
  "server": "${DOMAIN}",
  "server_port": ${PORT},
  "password": "${ANYTLS_PASSWORD}",
  "tls": {
    "enabled": true,
    "server_name": "${DOMAIN}"
  }
}
EOF
)

# 9. 保存信息文件并设置快捷打印脚本 info
cat <<EOF > /etc/sing-box/info.txt
====================================================
       Sing-box AnyTLS + Socks5 部署信息
====================================================
1. 【Socks5 节点一键导入链接】
   (适用客户端：苹果 Shadowrocket / 安卓 v2rayNG 、 NekoBox)
${SOCKS5_URL}
----------------------------------------------------
2. 【AnyTLS Shadowrocket 苹果小火箭 / NekoBox 客户端】
   (适用客户端：苹果 Shadowrocket / 安卓 NekoBox)
${ANYTLS_URL}
----------------------------------------------------
3. 【Sing-box AnyTLS Outbound JSON】
   (适用客户端：安卓 Sing-box / Clash Verge)
${CLIENT_JSON}
====================================================
EOF

# 创建快捷命令 `/usr/local/bin/info`
cat <<'EOF' > /usr/local/bin/info
#!/bin/bash
if [ -f /etc/sing-box/info.txt ]; then
    cat /etc/sing-box/info.txt
else
    echo "未检测到 Sing-box 配置信息，请重新运行安装脚本。"
fi
EOF

chmod +x /usr/local/bin/info

# 10. 打印最终配置输出
cat /etc/sing-box/info.txt
echo -e "${YELLOW}[提示] 后续随时输入 ${GREEN}info${YELLOW} 命令，即可重新打印以上节点信息！${PLAIN}"
echo -e "${GREEN}====================================================${PLAIN}"
