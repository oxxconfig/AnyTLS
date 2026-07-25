function install_anytls() {
    echo -e "\033[1;32m[+] 开始部署 AnyTLS 节点...\033[0m"

    # 1. 检查并安装 sing-box
    if ! command -v sing-box &> /dev/null; then
        echo -e "\033[1;34m[*] 正在安装 Sing-box 核心...\033[0m"
        bash <(curl -fsSL https://sing-box.app/deb-install.sh)
    fi

    # 2. 交互/自动获取变量 (可替换为你的脚本自动生成函数)
    read -p "请输入解析到本机 IP 的域名: " DOMAIN
    read -p "请输入 AnyTLS 监听端口 (默认 443): " PORT
    PORT=${PORT:-443}

    # 自动生成 Password / UUID
    PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)

    # 3. 申请证书路径 (假设已有证书，或调用 acme.sh)
    CERT_PATH="/etc/sing-box/cert/${DOMAIN}.crt"
    KEY_PATH="/etc/sing-box/cert/${DOMAIN}.key"

    # 4. 生成 sing-box 服务端 AnyTLS 配置文件
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
          "password": "${PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${DOMAIN}",
        "certificate_path": "${CERT_PATH}",
        "key_path": "${KEY_PATH}"
      },
      "detour": "web-fallback"
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

    # 5. 重启服务并开机自启
    systemctl restart sing-box
    systemctl enable sing-box

    # 6. 输出客户端连接信息
    echo -e "\033[1;32m========================================\033[0m"
    echo -e "\033[1;32m AnyTLS 节点部署成功！\033[0m"
    echo -e "\033[1;33m 域名 (SNI) : ${DOMAIN}\033[0m"
    echo -e "\033[1;33m 端口 (Port): ${PORT}\033[0m"
    echo -e "\033[1;33m 密码 (Password): ${PASSWORD}\033[0m"
    echo -e "\033[1;32m========================================\033[0m"
}
