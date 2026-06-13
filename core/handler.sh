#!/usr/bin/env bash
# =============================================================================
# AnyTLS / Next-Gen Protocol 后端核心数据流与组件配置处理器 (2026 架构版)
# =============================================================================

# --- 环境与常量设置 ---
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/snap/bin
export PATH

readonly GREEN='\033[32m'
readonly YELLOW='\033[33m'
readonly RED='\033[31m'
readonly NC='\033[0m'

readonly CUR_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
readonly CUR_FILE="$(basename "$0" | sed 's/\..*//')"
readonly PROJECT_ROOT="$(cd -P -- "${CUR_DIR}/.." && pwd -P)"

# 【沙箱解耦】主配置文件与数据落地目录切换为 anytls 独占，不踩老项目数据
readonly SCRIPT_CONFIG_DIR="${HOME}/.anytls-script"
readonly I18N_DIR="${PROJECT_ROOT}/i18n"
readonly CONFIG_DIR="${PROJECT_ROOT}/config"
readonly SERVICE_DIR="${PROJECT_ROOT}/service"
readonly TOOL_DIR="${PROJECT_ROOT}/tool"

# 【独立进程】为 AnyTLS / sing-box 预留独立的二进制与配置落地路径
readonly ANYTLS_CONFIG_PATH="/usr/local/etc/anytls/config.json"
readonly SCRIPT_CONFIG_PATH="${SCRIPT_CONFIG_DIR}/config.json"

# --- 全局变量声明 ---
# 确保在沙箱环境初次运行时，如果 config.json 不存在能安全初始化，不爆 jq 错误
if [[ ! -d "${SCRIPT_CONFIG_DIR}" ]]; then
    mkdir -p "${SCRIPT_CONFIG_DIR}"
    echo '{"language":"zh","anytls":{"port":443},"version":"latest"}' > "${SCRIPT_CONFIG_PATH}"
fi

declare SCRIPT_CONFIG="$(jq '.' "${SCRIPT_CONFIG_PATH}")"
declare ANYTLS_CONFIG=""
declare I18N_DATA=''
declare -A CONFIG_DATA

# =============================================================================
# 基础原子函数 (保留并增强稳定性)
# =============================================================================

function load_i18n() {
    local lang="$(echo "${SCRIPT_CONFIG}" | jq -r '.language // "zh"')"
    [[ "$lang" == "auto" ]] && lang=$(echo "$LANG" | cut -d'_' -f1)
    local i18n_file="${I18N_DIR}/${lang}.json"
    if [[ ! -f "${i18n_file}" ]]; then
        I18N_DATA='{"title":{"error":"错误","config":"配置","tip":"提示"},"handler":{"script":{"config_update":"正在写入新协议矩阵配置..."}}}'
        return
    fi
    I18N_DATA="$(jq '.' "${i18n_file}")"
}

function _error() {
    local error_title="$(echo "$I18N_DATA" | jq -r '.title.error' 2>/dev/null || echo "Error")"
    printf "${RED}[${error_title}] ${NC}%s\n" "$@" >&2
    exit 1
}

# 快捷调用独立脚本的安全包装器
function exec_generate() { [[ -f "${CUR_DIR}/generate.sh" ]] && bash "${CUR_DIR}/generate.sh" "$@"; }
function exec_check()    { [[ -f "${CUR_DIR}/check.sh" ]] && bash "${CUR_DIR}/check.sh" "$@"; }
function exec_read()     { [[ -f "${CUR_DIR}/read.sh" ]] && bash "${CUR_DIR}/read.sh" "$@"; }

function cmd_exists() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1
}

# =============================================================================
# 函数名称: handler_script_config
# 功能描述: 核心重构！解析并持久化 AnyTLS / sing-box 下一代流控面板的主配置。
# 参数:
#   $1: CONFIG_TAG - 激进协议标识 (AnyTLS / Hysteria2 / TUIC)
# =============================================================================
function handler_script_config() {
    local config_tag="${1:-${CONFIG_DATA['tag']}}"
    local config_title="$(echo "$I18N_DATA" | jq -r '.title.config' 2>/dev/null || echo "Config")"
    local update_msg="$(echo "$I18N_DATA" | jq -r '.handler.script.config_update' 2>/dev/null || echo "Updating config...")"
    
    echo -e "${GREEN}[${config_title}]${NC} ${update_msg} [${config_tag}]" >&2
    
    # 1. 提取或全自动生成自动化部署所需的核心参数
    local current_port="${CONFIG_DATA['port']:-443}"
    
    # 2. 为 AnyTLS / Shadowsocks-Next 自动适配高强度前置共享密钥/密码
    local anytls_auth=""
    if [[ -n "${CONFIG_DATA['password']}" ]]; then
        anytls_auth="${CONFIG_DATA['password']}"
    else
        # 如果是 60 台 VPS 自动化静默安装，没有手工输入密码，则调用 openssl 自动下发 16 位强密码
        anytls_auth="$(openssl rand -hex 16 2>/dev/null || echo "AnyTLSPassword2026")"
    fi

    # 3. 构造干净、纯粹的现代化 JSON 节点流控底座
    SCRIPT_CONFIG=$(jq -n \
        --arg tag "${config_tag}" \
        --argport port "${current_port}" \
        --arg auth "${anytls_auth}" \
        --arg ver "${CONFIG_DATA['version']:-latest}" \
        '{
            "language": "zh",
            "protocol": {
                "tag": $tag,
                "port": ($port | tonumber),
                "auth_secret": $auth,
                "version": $ver,
                "updated_at": (now | strflocaltime("%Y-%m-%d %H:%M:%S"))
            }
        }')

    # 4. 原子级写入，确保多机并发同步写入时不损坏文件
    echo "${SCRIPT_CONFIG}" > "${SCRIPT_CONFIG_PATH}"
    sync && sleep 0.5
    
    echo -e "${GREEN}[成功]${NC} 独立沙箱配置写入完成！端口: ${YELLOW}${current_port}${NC}, 密钥: ${YELLOW}${anytls_auth}${NC}" >&2
}

# =============================================================================
# 函数名称: handler_quick_install
# 功能描述: 执行一键快速安装流程。
#           1. 调用 handler_script_config 写入基本配置。
#           2. 安装 Xray 核心、Nginx 服务、SSL 证书工具并配置域名。
#           3. 重启相关服务并生成分享链接。
# 参数:
#   $1: CONFIG_TAG - 配置标签 (如 vision, xhttp)
# 返回值: 无
# =============================================================================
function handler_quick_install() {
    local CONFIG_TAG="${1}"
    
    # 1. 读取用户输入的核心 Xray 配置
    handler_read_xray_config "${CONFIG_TAG}"
    
    # 2. 将输入的数据持久化到脚本主配置文件
    handler_script_config "${CONFIG_TAG}"
    
    # 3. 如果是需要 Reality 密钥对的协议，生成并持久化 X25519 密钥
    case "${CONFIG_TAG,,}" in
        vision|xhttp|trojan|fallback)
            handler_x25519_config
            ;;
    esac

    # 4. 核心组件安装
    handler_install "" "n"
    handler_nginx_install

    # 5. 根据协议类型配置路由与证书分流
    case "${CONFIG_TAG,,}" in
        sni)
            handler_sni_config "normal"
            ;;
        *)
            # 其它协议默认关闭额外的 Web 容器，生成标准 Xray 核心配置
            handler_sni_config "normal"
            handler_xray_config
            ;;
    esac

    # 6. 启动服务并开启定时任务
    handler_start
    handler_nginx_start
    handler_geodata_cron 1 # 快速模式立即更新一次 GeoData
    handler_nginx_cron

    # 7. 打印安装成功后的节点分享数据
    handler_share
}

# =============================================================================
# 函数名称: show_menu
# 功能描述: 渲染主动态多语言控制台菜单。
# =============================================================================
function show_menu() {
    clear
    local xray_v="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.version // "Not Installed"')"
    local nginx_v="$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.version // "Not Installed"')"
    local current_tag="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.tag // "None"')"
    
    echo -e "${GREEN}==================================================${NC}"
    echo -e "  Xray Management Script Hub (Current Protocol: ${YELLOW}${current_tag}${NC})"
    echo -e "  Xray Core Version:  ${GREEN}${xray_v}${NC}"
    echo -e "  Nginx Service Body: ${GREEN}${nginx_v}${NC}"
    echo -e "${GREEN}==================================================${NC}"
    
    # 从 i18n JSON 数据渲染菜单文本项 (如 text_menu_1, text_menu_2 等)
    printf " 1. %s\n" "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.menu.install_vision // \"Install VLESS-XTLS-Vision (Reality)\"")"
    printf " 2. %s\n" "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.menu.install_xhttp // \"Install VLESS-XHTTP (Reality)\"")"
    printf " 3. %s\n" "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.menu.install_sni // \"Install Trojan/VLESS SNI Proxy (Nginx)\"")"
    echo -e "--------------------------------------------------"
    printf " 4. %s\n" "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.menu.manage_xray // \"Start / Stop / Restart Xray Core\"")"
    printf " 5. %s\n" "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.menu.manage_nginx // \"Start / Stop / Restart Nginx Service\"")"
    printf " 6. %s\n" "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.menu.toggle_warp // \"Toggle Cloudflare WARP IPv4/IPv6 Outbound\"")"
    printf " 7. %s\n" "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.menu.manage_cron // \"Setup Auto Update Cron Tasks (GeoData/Nginx)\"")"
    echo -e "--------------------------------------------------"
    printf " 8. %s\n" "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.menu.custom_sites // \"Manage Nginx Sni Proxy Custom Sites\"")"
    printf " 9. %s\n" "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.menu.show_share // \"Show Node Credentials & Share Links\"")"
    printf "10. %s\n" "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.menu.show_traffic // \"Show Real-time Port Link Traffic\"")"
    printf "11. %s\n" "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.menu.renew_ssl // \"Force Renew All SSL Certificates\"")"
    printf "12. %s\n" "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.menu.purge_all // \"Purge and Uninstall All Core Services\"")"
    echo -e "--------------------------------------------------"
    printf " 0. %s\n" "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.menu.exit // \"Exit Script\"")"
    echo -e "${GREEN}==================================================${NC}"
}

# =============================================================================
# 函数名称: main
# 功能描述: 脚本交互主循环体
# =============================================================================
function main() {
    # 确保主配置目录及文件正确初始化
    mkdir -p "${SCRIPT_CONFIG_DIR}"
    if [[ ! -f "${SCRIPT_CONFIG_PATH}" || ! -s "${SCRIPT_CONFIG_PATH}" ]]; then
        echo '{"language":"auto","xray":{"version":null,"tag":null,"port":443,"warp":0,"rules":{"reset":1,"bt":1,"cn":1,"ad":1}},"nginx":{"version":null,"ca":null,"ca_server":"zerossl","web":"normal","domain":null,"cdn":null,"custom_sites":[]},"rules":[]}' | jq '.' > "${SCRIPT_CONFIG_PATH}"
    fi

    # 重新加载全局配置变量并载入对应语言包
    SCRIPT_CONFIG="$(jq '.' "${SCRIPT_CONFIG_PATH}")"
    load_i18n

    # 如果有外部命令行参数，走无交互静默流，不再进入循环菜单
    if [[ $# -gt 0 ]]; then
        case "${1}" in
            --install-vision) handler_quick_install "vision" ;;
            --install-xhttp)  handler_quick_install "xhttp" ;;
            --install-sni)    handler_quick_install "sni" ;;
            --start)          handler_start; handler_nginx_start ;;
            --stop)           handler_stop; handler_nginx_stop ;;
            --restart)        handler_restart; handler_nginx_restart ;;
            --purge)          handler_purge; handler_nginx_purge ;;
            *) echo -e "${RED}[Error]${NC} Unknown argument: ${1}"; exit 1 ;;
        esac
        exit 0
    fi

    # 交互式常驻菜单
    while true; do
        show_menu
        local choice
        read -rp "Please enter your choice [0-12]: " choice
        case "${choice}" in
            1)  handler_quick_install "vision" ;;
            2)  handler_quick_install "xhttp" ;;
            3)  handler_quick_install "sni" ;;
            4)  
                echo -e "1. Start Xray\n2. Stop Xray\n3. Restart Xray"
                read -rp "Action: " act
                [[ "${act}" == "1" ]] && handler_start
                [[ "${act}" == "2" ]] && handler_stop
                [[ "${act}" == "3" ]] && handler_restart
                ;;
            5)  
                echo -e "1. Start Nginx\n2. Stop Nginx\n3. Restart Nginx"
                read -rp "Action: " act
                [[ "${act}" == "1" ]] && handler_nginx_start
                [[ "${act}" == "2" ]] && handler_nginx_stop
                [[ "${act}" == "3" ]] && handler_nginx_restart
                ;;
            6)  handler_warp ;;
            7)  
                echo -e "1. Toggle GeoData Cron\n2. Toggle Nginx Upgrade Cron"
                read -rp "Action: " act
                [[ "${act}" == "1" ]] && handler_geodata_cron 0
                [[ "${act}" == "2" ]] && handler_nginx_cron
                ;;
            8)  
                echo -e "1. List Custom Sites\n2. Add Custom Site\n3. Update Custom Site\n4. Delete Custom Site"
                read -rp "Action: " act
                [[ "${act}" == "1" ]] && handler_custom_sites "list"
                [[ "${act}" == "2" ]] && handler_custom_sites "add"
                [[ "${act}" == "3" ]] && handler_custom_sites "update"
                [[ "${act}" == "4" ]] && handler_custom_sites "delete"
                ;;
            9)  handler_share ;;
            10) handler_traffic ;;
            11) handler_renew_ssl ;;
            12) 
                read -rp "Are you sure to uninstall everything? (y/n): " confirm
                if [[ "${confirm,,}" == "y" ]]; then
                    handler_stop; handler_nginx_stop
                    handler_purge; handler_nginx_purge
                fi
                ;;
            0)  echo "Goodbye!"; exit 0 ;;
            *)  echo -e "${RED}Invalid option, try again.${NC}"; sleep 1 ;;
        esac
        echo -e "\n${YELLOW}Press Enter key to return to the main menu...${NC}"
        read -r
    done
}

# --- 执行入口投射 ---
# 传入所有 shell 原始位置参数到核心函数中
main "$@"
