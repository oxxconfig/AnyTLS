#!/bin/bash

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

echo -e "${YELLOW}===========================================${PLAIN}"
echo -e "${YELLOW}        Sing-box 卸载/清理管理脚本         ${PLAIN}"
echo -e "${YELLOW}===========================================${PLAIN}"
echo -e " 1. ${GREEN}测试快速重置${PLAIN} (保留证书，仅重置配置，适合测试调试)"
echo -e " 2. ${RED}彻底卸载清理${PLAIN} (删除所有配置、证书、acme.sh 及服务)"
echo -e " 0. 退出"
echo -e "-------------------------------------------"
read -p "请选择操作 [0-2]: " CHOICE

case "$CHOICE" in
    1)
        echo -e "${BLUE}[*] 正在进行测试期快速重置...${PLAIN}"
        systemctl stop sing-box &>/dev/null
        systemctl disable sing-box &>/dev/null
        rm -f /etc/sing-box/config.json /etc/sing-box/info.txt
        rm -f /usr/local/bin/info
        echo -e "${GREEN}[+] 重置完成！已保留 /etc/sing-box/cert 目录下的证书。${PLAIN}"
        ;;
    2)
        echo -e "${RED}[*] 正在彻底清理 Sing-box 及所有环境...${PLAIN}"
        systemctl stop sing-box &>/dev/null
        systemctl disable sing-box &>/dev/null
        rm -f /etc/systemd/system/sing-box.service
        systemctl daemon-reload
        rm -rf /etc/sing-box /var/lib/sing-box /usr/local/bin/sing-box /usr/local/bin/info
        rm -rf ~/.acme.sh
        if crontab -l &>/dev/null; then
            crontab -l | grep -v "acme.sh" | crontab -
        fi
        echo -e "${GREEN}=== Sing-box 及相关环境已彻底卸载清理干净！ ===${PLAIN}"
        ;;
    *)
        echo -e "${YELLOW}已取消操作。${PLAIN}"
        exit 0
        ;;
esac
