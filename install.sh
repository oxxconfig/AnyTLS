#!/usr/bin/env bash
# =============================================================================
# AnyTLS / Next-Gen Protocol 批量静默部署前置增强脚本 (2026 分支版)
# =============================================================================

# 1. 严格权限断言 (彻底废除无意义的 sudo)
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[31m[错误] 请使用 root 用户或 sudo 运行此脚本！\033[0m"
    exit 1
fi

# 2. 全局环境变量压制（全面禁绝弹窗交互）
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/snap/bin
export PATH

# 3. 备份原始参数，防止 while 消费导致更新功能丢失参数
ORIGINAL_ARGS=("$@")

readonly GREEN='\033[32m'
readonly YELLOW='\033[33m'
readonly RED='\033[31m'
readonly NC='\033[0m'

readonly CUR_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
readonly CUR_FILE="$(basename "$0")"

# 【关键隔离点 1】独立本地配置目录，防止覆盖老 Xray 脚本的配置
readonly SCRIPT_CONFIG_DIR="${HOME}/.anytls-script"
readonly SCRIPT_CONFIG_PATH="${SCRIPT_CONFIG_DIR}/config.json"

declare PROJECT_ROOT=''
declare CORE_DIR=''
declare QUICK_INSTALL=''
declare LANG_PARAM='--lang=zh'
declare FORCE_CHECK_DEPS=0

# 【关键配置项】请在新建仓库后，将下述两处替换为你专属的新仓库名称
readonly GITHUB_USER="oxxconfig"
readonly GITHUB_REPO="Xray-AnyTLS"  # 假设你新仓库叫这个，如果叫别的请在此处修改

function _os() {
    if [[ -f "/etc/debian_version" ]]; then
        local os_id
        os_id=$(grep -oP '^ID=\K\w+' /etc/os-release 2>/dev/null || echo "ubuntu")
        printf -- "%s" "${os_id}"
        return
    fi
    [[ -f "/etc/redhat-release" ]] && printf -- "centos" && return
    printf -- "ubuntu"
}

# 深度优化内核性能（针对 AnyTLS 大量密集分包、流量混淆填充进行优化）
function init_env_optimization() {
    echo -e "${GREEN}[基础配置]${NC} 开始优化系统内核与防火墙规则..."
    
    # 清理网络队列旧残留
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    sed -i '/net.core.rmem_max/d' /etc/sysctl.conf
    sed -i '/net.core.wmem_max/d' /etc/sysctl.conf

    # 注入现代流控标准：BBR + FQ + 高上限吞吐量缓存配置
    cat << 'EOF' >> /etc/sysctl.conf

# Network Optimization By AnyTLS Deployer
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.ipv4.tcp_rmem=4096 87380 33554432
net.ipv4.tcp_wmem=4096 65536 33554432
EOF
    sysctl -p >/dev/null 2>&1

    # 防火墙端口自动化放行（支持批量非标准端口静默下发）
    if type iptables >/dev/null 2>&1; then
        if ! iptables -L INPUT -n 2>/dev/null | grep -q "dpt:443"; then
            iptables -I INPUT -p tcp --dport 443 -j ACCEPT
            echo -e "${GREEN}[基础配置]${NC} 防火墙已放行 TCP 443 端口 (AnyTLS默认)"
            
            # 规则持久化
            if type iptables-save >/dev/null 2>&1; then
                iptables-save > /etc/iptables.rules 2>/dev/null || true
            fi
            if type netfilter-persistent >/dev/null 2>&1; then
                netfilter-persistent save >/dev/null 2>&1 || true
            fi
        fi
    fi
}

function check_dependencies() {
    local packages=("ca-certificates" "openssl" "curl" "wget" "git" "jq" "tzdata" "qrencode" "socat")
    local missing=0

    if [[ "$(_os)" == "centos" ]]; then
        packages+=("crontabs" "util-linux" "iproute" "procps-ng" "bind-utils")
        for pkg in "${packages[@]}"; do
            rpm -q "$pkg" &>/dev/null || missing=$((missing+1))
        done
    else
        if apt-cache show bsdextrautils &>/dev/null; then
            packages+=("cron" "bsdextrautils" "iproute2" "procps" "dnsutils")
        else
            packages+=("cron" "bsdmainutils" "iproute2" "procps" "dnsutils")
        fi

        for pkg in "${packages[@]}"; do
            dpkg -s "$pkg" &>/dev/null || missing=$((missing+1))
        done
    fi

    if [ $missing -eq 0 ]; then return 0; else return 1; fi
}

function install_dependencies() {
    if [[ "$(_os)" == "centos" ]]; then
        local packages=("ca-certificates" "openssl" "curl" "wget" "git" "jq" "tzdata" "qrencode" "socat" "crontabs" "util-linux" "iproute" "procps-ng" "bind-utils")
        if type dnf >/dev/null 2>&1; then
            dnf update -y && dnf install -y dnf-plugins-core
            for pkg in "${packages[@]}"; do dnf install -y "${pkg}"; done
        else
            yum update -y && yum install -y epel-release yum-utils
            for pkg in "${packages[@]}"; do yum install -y "${pkg}"; done
        fi
    else
        apt-get update -y -o Acquire::Retries=3 -o Acquire::http::Timeout=10
        local packages=("ca-certificates" "openssl" "curl" "wget" "git" "jq" "tzdata" "qrencode" "socat" "cron" "iproute2" "procps" "dnsutils")
        if apt-cache show bsdextrautils &>/dev/null; then packages+=("bsdextrautils"); else packages+=("bsdmainutils"); fi
        for pkg in "${packages[@]}"; do
            apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" "${pkg}"
        done
    fi
}

function download_github_files() {
    local target_dir="$1"
    local github_api_url="$2"
    
    mkdir -p "${target_dir}"
    cd "${target_dir}" || exit 1
    echo -e "${GREEN}[下载核心]${NC} 正在同步新项目后端业务资产..."
    
    rm -f temp_archive.tar.gz
    if ! curl -sLo temp_archive.tar.gz "${github_api_url}"; then
        echo -e "${RED}[错误]${NC} 网络异常，拉取新仓库失败！"
        exit 1
    fi
    
    if ! tar -xzf temp_archive.tar.gz --no-same-owner 2>/dev/null; then
        echo -e "${RED}[错误]${NC} 核心解压损坏！"
        rm -f temp_archive.tar.gz
        exit 1
    fi
    
    local root_dir
    root_dir=$(tar -tzf temp_archive.tar.gz | head -1 | cut -f1 -d'/')
    if [[ -n "${root_dir}" && -d "${root_dir}" ]]; then
        cp -r "${root_dir}"/* ./ 2>/dev/null || true
        rm -rf "${root_dir}"
    fi
    rm -f temp_archive.tar.gz
}

function download_script_files_from_new_repo() {
    # 动态锚定新仓库的 main 分支
    download_github_files "$1" "https://github.com/${GITHUB_USER}/${GITHUB_REPO}/archive/refs/heads/main.tar.gz"
}

function check_script_version() {
    local script_config_github_url="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main/config.json"
    local local_version remote_version
    local_version="$(jq -r '.version' "${SCRIPT_CONFIG_PATH}" 2>/dev/null || echo "0.0.0")"
    remote_version="$(curl -fsSL --connect-timeout 5 "$script_config_github_url" | jq -r '.version' 2>/dev/null || echo "0.0.0")"

    if [[ "${local_version}" != "${remote_version}" && "${remote_version}" != "0.0.0" ]]; then
        echo -e "${GREEN}[更新提示]${NC} 检测到 AnyTLS 分支有新发布，增量同步中..."
        cd "${HOME}" || exit 1
        local temp_dir="${SCRIPT_CONFIG_DIR}/anytls-script-temp"
        mkdir -p "${temp_dir}"
        download_script_files_from_new_repo "${temp_dir}"
        
        if [[ -n "${PROJECT_ROOT}" && "${PROJECT_ROOT}" != "/" && "${PROJECT_ROOT}" != "/root" ]]; then
            rm -rf "${PROJECT_ROOT}"
        fi
        
        mv -f "${temp_dir}" "${PROJECT_ROOT}"
        rm -f "${CUR_DIR}/${CUR_FILE}"
        cp -f "${PROJECT_ROOT}/install.sh" "${CUR_DIR}/${CUR_FILE}"
        sed -i "s|${local_version}|${remote_version}|" "${SCRIPT_CONFIG_PATH}" 2>/dev/null
        echo -e "${GREEN}[更新提示]${NC} 新分支热同步完成，正在恢复参数重新重载..."
        
        exec bash "${CUR_DIR}/${CUR_FILE}" "${ORIGINAL_ARGS[@]}"
    fi
}

function main() {
    # 扩展参数流：完美接纳下一代全混淆协议
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --anytls | --reality | --hysteria2 | --tuic) QUICK_INSTALL="${1}" ;;
        -d) shift; PROJECT_ROOT="${1}" ;;
        esac
        shift
    done

    init_env_optimization

    if check_dependencies; then
        echo -e "${GREEN}[基础配置]${NC} 核心环境依赖检测完整，跳过安装"
    else
        echo -e "${YELLOW}[基础配置]${NC} 正在补全系统核心环境依赖..."
        install_dependencies
    fi

    if [[ ! -d "${SCRIPT_CONFIG_DIR}" ]]; then mkdir -p "${SCRIPT_CONFIG_DIR}"; fi

    # 【关键隔离点 2】赋予独立的新版本号及本地落地路径，默认部署在 anytls-script 下
    if [[ ! -f "${SCRIPT_CONFIG_PATH}" ]]; then
        wget --timeout=10 -O "${SCRIPT_CONFIG_PATH}" https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main/config.json || \
        echo '{"version":"2026.06.01-anytls","language":"zh","path":"/usr/local/anytls-script"}' > "${SCRIPT_CONFIG_PATH}"
    fi

    local script_path
    script_path="$(jq -r '.path' "${SCRIPT_CONFIG_PATH}" 2>/dev/null || echo "")"
    if [[ -z "${script_path}" && -z "${PROJECT_ROOT}" ]]; then
        PROJECT_ROOT='/usr/local/anytls-script'
        local json_payload
        json_payload=$(jq --arg path "${PROJECT_ROOT}" '.path = $path' "${SCRIPT_CONFIG_PATH}" 2>/dev/null)
        [[ -n "${json_payload}" ]] && echo "${json_payload}" >"${SCRIPT_CONFIG_PATH}"
    elif [[ -n "${script_path}" ]]; then
        PROJECT_ROOT="${script_path}"
    fi

    if [[ -z "${PROJECT_ROOT}" || "${PROJECT_ROOT}" == "/" || "${PROJECT_ROOT}" == "/root" ]]; then
        echo -e "${RED}[核心防御] 路径安全熔断！\033[0m"
        exit 1
    fi

    CORE_DIR="${PROJECT_ROOT}/core"

    if [[ -d "${PROJECT_ROOT}" && -f "${CORE_DIR}/main.sh" ]]; then
        check_script_version "${ORIGINAL_ARGS[@]}"
    else
        rm -rf "${PROJECT_ROOT}"
        download_script_files_from_new_repo "${PROJECT_ROOT}"
    fi

    local json_lang
    json_lang=$(jq --arg language "zh" '.language = $language' "${SCRIPT_CONFIG_PATH}" 2>/dev/null)
    [[ -n "${json_lang}" ]] && echo "${json_lang}" >"${SCRIPT_CONFIG_PATH}"

    # 【关键隔离点 3】更改别名注册。输入 anytls 即可唤起全新的业务控制台
    if [ -f "${CORE_DIR}/main.sh" ]; then
        local target_rcs=("${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile")
        for rc in "${target_rcs[@]}"; do
            if [[ -f "${rc}" || "${rc}" == "${HOME}/.bashrc" ]]; then
                sed -i '/alias anytls=/d' "${rc}" 2>/dev/null || true
                echo "alias anytls='bash ${CORE_DIR}/main.sh'" >> "${rc}"
            fi
        done
    fi

    echo -e "${GREEN}[部署完成]${NC} 新项目依赖与内核优化已就绪，正在唤起 AnyTLS 核心业务脚本..."
    echo "--------------------------------------------------------"
    
    exec bash "${CORE_DIR}/main.sh" "${QUICK_INSTALL}"
}

main "${ORIGINAL_ARGS[@]}"
