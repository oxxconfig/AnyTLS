systemctl stop sing-box &>/dev/null
systemctl disable sing-box &>/dev/null
rm -f /etc/systemd/system/sing-box.service
systemctl daemon-reload
rm -rf /etc/sing-box /var/lib/sing-box /usr/local/bin/sing-box ~/.acme.sh
crontab -l | grep -v "acme.sh" | crontab -
echo "=== Sing-box 及相关环境已彻底卸载清理干净 ==="
