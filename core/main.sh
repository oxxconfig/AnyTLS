#!/usr/bin/env bash
# =============================================================================
# AnyTLS / Next-Gen Protocol 核心业务调度控制器 (2026 架构版)
# =============================================================================

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/snap/bin
export PATH

readonly GREEN='\033[32m'
readonly YELLOW='\033[33m'
readonly RED='\033[31m'
readonly NC='\033[0m'

readonly CUR_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
readonly CUR_FILE="$(basename "$0" | sed 's/\..*//')"
readonly PROJECT_ROOT="$(cd -P -- "${CUR_DIR}/.." && pwd -P)"

# 【隔离核心】将配置文件目录锚定到 anytls 的独立沙箱中，决不破坏旧生产环境
readonly SCRIPT_CONFIG_DIR="${HOME}/.anytls-script"
readonly I18N_DIR="${PROJECT_ROOT}/i18n"
readonly CONFIG_DIR="${PROJECT_ROOT}/config"
readonly MENU_PATH="${CUR_DIR}/menu.sh"
readonly HANDLER_PATH="${CUR_DIR}/handler.sh"
readonly SCRIPT_CONFIG_PATH="${SCRIPT_CONFIG_DIR}/config.json"

declare LANG_PARAM=''
declare I18N_DATA=''
declare SCRIPT_CONFIG=''

function load_i18n() {
    local lang="$(jq -r '.language' "${SCRIPT_CONFIG_PATH}" 2>/dev/null || echo "zh")"
    if [[ "$lang" == "auto" ]]; then
        lang=$(echo "$LANG" | cut -d'_' -f1)
    fi
    local i18n_file="${I18N_DIR}/${lang}.json"
    if [[ ! -f "${i18n_file}" ]]; then
        # 如果新仓库还没配置好 i18n 资产，提供骨架保底，防止脚本直接崩溃
        I18N_DATA='{"title":{"error":"错误"},"main":{"handler_failed":"处理器执行失败"}}'
        return
    fi
    I18N_DATA="$(jq '.' "${i18n_file}")"
}

function _error() {
    printf "${RED}[$(echo "$I18N_DATA" | jq -r '.title.error' 2>/dev/null || echo "Error")] ${NC}"
    printf -- "%s" "$@"
    printf "\n"
    exit 1
}

function exec_menu() {
    local OPTION=0
    if [[ -f "${MENU_PATH}" ]]; then
        bash "${MENU_PATH}" "$@"
        OPTION=$?
    fi
    return ${OPTION}
}

function exec_handler() {
    if [[ -f "${HANDLER_PATH}" ]]; then
        bash "${HANDLER_PATH}" "$@"
        local exit_code=$?
        if [[ ${exit_code} -ne 0 ]]; then
            _error "执行失败: handler.sh $1"
        fi
    else
        echo -e "${YELLOW}[调试]${NC} 静默拦截未实现的后端动作: $1 $2"
    fi
}

# --- 新增：下一代全混淆协议批量静默安装下发引擎 ---
function deploy_nextgen_protocol() {
    local proto_type="${1}"
    echo -e "${GREEN}[核心启动]${NC} 正在通过纯净沙箱批量部署 ${GREEN}${proto_type}${NC} 节点..."
    
    # 示例自动化逻辑：
    # 1. 阻止任何交互弹窗
    # 2. 生成随机高位端口与 AnyTLS 密码密钥
    # 3. 动态改写 ${SCRIPT_CONFIG_DIR}/config.json
    # 4. 唤醒调用你的特定编译版本或下发进程
    
    # 现阶段我们先做安全代理拦截，方便你后续在 handler.sh 里大刀阔斧地写逻辑
    exec_handler '--quick' "${proto_type}"
}

function processes_index() {
    # 如果敲 anytls 进入了交互界面
    exec_menu '--banner'
    echo -e "${GREEN} 欢迎使用 AnyTLS / sing-box 下一代高性能自动化面板${NC}"
    echo "--------------------------------------------------------"
    echo -e " 老项目的 Xray 运行环境已在系统层解耦隔离。"
    echo -e " 提示：你可以安全地在底层重构 handler.sh 脚本。"
    echo "--------------------------------------------------------"
    
    exec_menu '--status'
    exec_menu '--index'
    local choose=$(echo $?)
    case ${choose} in
    1) deploy_nextgen_protocol 'AnyTLS' ;; # 将主菜单的一键安装默认导向新协议测试
    2) exec_handler '--install' ;;
    3) exec_handler '--purge' ;;
    4) exec_handler '--start' ;;
    5) exec_handler '--stop' ;;
    6) exec_handler '--restart' ;;
    7) exec_handler '--share' ;;
    *) exit 0 ;;
    esac
}

function main() {
    load_i18n
    
    # 核心拦截器：完美承接前置安装脚本传过来的激进新协议参数
    case "${1,,}" in
    --anytls)     deploy_nextgen_protocol 'AnyTLS' ;;
    --hysteria2)  deploy_nextgen_protocol 'Hysteria2' ;;
    --tuic)       deploy_nextgen_protocol 'TUIC' ;;
    --vision)     exec_handler '--quick' 'Vision' ;;
    *)            processes_index "$2" ;;
    esac
}

main "$@"
