#!/bin/bash

# 修正并优化后的 AnyTLS + Socks5 一键部署函数
function install_anytls_and_socks5() {
    echo -e "\033[1;32m[+] 开始部署 AnyTLS + Socks5 节点...\033[0m"

    # 1. 安装基础依赖与 sing-box 预发版 (AnyTLS 需 1.11.0+)
    echo -e "\033[1;34m[*] 检查依赖及安装最新 Sing-box 核心...\033[0m"
    apt-get update && apt-get install -y curl socat cron tar jq &> /dev/null || yum install -y curl socat crontabs tar jq &> /dev/null
    
    # 强制安装/更新支持 AnyTLS 的 Sing-box 预发版本 (pre-release)
    bash <(curl -fsSL https://sing-box.app/deb-install.sh) --prerelease

    # 2. 交互/自动获取变量
    read -p "请输入解析到本机 IP 的域名: " DOMAIN
    if [ -z "$DOMAIN" ]; then
        echo -e "\033[1;31m[-] 必须输入有效域名！部署终止。\033[0m"
        return 1
    fi

    read -p "请输入 AnyTLS 监听端口 (默认 443): " PORT
    PORT=${PORT:-443}

    read -p "请输入 Socks5 监听端口 (默认 1080): " SOCKS_PORT
    SOCKS_PORT=${SOCKS_PORT:-1080}

    # 自动生成随机账号密码
    ANYTLS_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    SOCKS_USER="user_$(head /dev/urandom | tr -dc 0-9 | head -c 4)"
    SOCKS_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)

    # 3. 自动申请 Let's Encrypt 证书
    echo -e "\033[1;34m[*] 正在通过 acme.sh 申请 TLS 证书...\033[0m"
    CERT_DIR="/etc/sing-box/cert"
    mkdir -p "${CERT_DIR}"
    CERT_PATH="${CERT_DIR}/${DOMAIN}.crt"
    KEY_PATH="${CERT_DIR}/${DOMAIN}.key"

    if [ ! -f "$CERT_PATH" ]; then
        # 安装 acme.sh
        curl https://get.acme.sh | sh -s email=admin@${DOMAIN} &> /dev/null
        ~/.acme.sh/acme.sh --upgrade --auto-upgrade &> /dev/null
        
        # 释放 80 端口申请证书
        systemctl stop nginx &> /dev/null
        ~/.acme.sh/acme.sh --issue -d ${DOMAIN} --standalone -k ec-256
        ~/.acme.sh/acme.sh --install-cert -d ${DOMAIN} --ecc \
            --fullchain-file "${CERT_PATH}" \
            --key-file "${KEY_PATH}"
    fi

    if [ ! -f "$CERT_PATH" ]; then
        echo -e "\033[1;31m[-] 证书申请失败，请确认 80 端口未被占用且域名解析正确！\033[0m"
        return 1
    fi

    # 4. 生成包含 AnyTLS、Socks5 以及 Fallback 回落机制的配置
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

    # 5. 测试配置并重启服务
    sing-box check -c /etc/sing-box/config.json
    if [ $? -ne 0 ]; then
        echo -e "\033[1;31m[-] Sing-box 配置文件格式验证失败！\033[0m"
        return 1
    fi

    systemctl restart sing-box
    systemctl enable sing-box &> /dev/null

    # 6. 打印客户端信息
    echo -e "\033[1;32m========================================\033[0m"
    echo -e "\033[1;32m  AnyTLS + Socks5 节点部署完成！ \033[0m"
    echo -e "\033[1;32m========================================\033[0m"
    echo -e "\033[1;33m[AnyTLS 配置]\033[0m"
    echo -e " 域名 (SNI) : ${DOMAIN}"
    echo -e " 端口 (Port): ${PORT}"
    echo -e " 密码 (Password): ${ANYTLS_PASSWORD}"
    echo -e "----------------------------------------"
    echo -e "\033[1;33m[Socks5 配置]\033[0m"
    echo -e " 端口 (Port): ${SOCKS_PORT}"
    echo -e " 账号 (User): ${SOCKS_USER}"
    echo -e " 密码 (Pass): ${SOCKS_PASS}"
    echo -e "\033[1;32m========================================\033[0m"
}
