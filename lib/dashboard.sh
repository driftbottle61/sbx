#!/bin/bash

# SBX CLI dashboard.
#
# Design goals:
#   - first frame is fast: version/network probes are cached or backgrounded
#   - no full-screen clear on refresh: redraw in place, erase each line first
#   - readable hierarchy instead of one dense block of key/value pairs
#   - works without color, without a TTY, and on narrow terminals

DASH_LINES=()
DASHBOARD_STATIC_LOADED="${DASHBOARD_STATIC_LOADED:-0}"

dashboard_color_enabled(){
    case "${SBX_DASHBOARD_COLOR:-auto}" in
        always) return 0 ;;
        never) return 1 ;;
    esac
    [ -t 1 ] || return 1
    [ "${TERM:-}" != "dumb" ] || return 1
    [ -z "${NO_COLOR:-}" ] || return 1
    return 0
}

dashboard_init(){
    if dashboard_color_enabled; then
        C_RESET=$'\033[0m'
        C_BOLD=$'\033[1m'
        C_DIM=$'\033[2m'
        C_CYAN=$'\033[36m'
        C_GREEN=$'\033[32m'
        C_YELLOW=$'\033[33m'
        C_RED=$'\033[31m'
    else
        C_RESET=""
        C_BOLD=""
        C_DIM=""
        C_CYAN=""
        C_GREEN=""
        C_YELLOW=""
        C_RED=""
    fi
    if [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
        DASHBOARD_TTY=1
    else
        DASHBOARD_TTY=0
    fi
}

dash_cols(){
    local cols="${COLUMNS:-}"
    if [ -z "$cols" ] || ! [[ "$cols" =~ ^[0-9]+$ ]]; then
        cols="$(tput cols 2>/dev/null || echo 80)"
    fi
    case "$cols" in
        ''|*[!0-9]*) cols=80 ;;
    esac
    [ "$cols" -lt 60 ] && cols=60
    [ "$cols" -gt 100 ] && cols=100
    printf '%s' "$cols"
}

dash_fill(){
    local n="$1" i out=""
    [ "$n" -lt 1 ] && n=1
    for ((i = 0; i < n; i++)); do
        out+="─"
    done
    printf '%s' "$out"
}

dash_add(){
    DASH_LINES+=("$1")
}

dash_rule(){
    local title="$1" cols="$2" title_w="${3:-}" left left_w n
    if [ -n "$title" ]; then
        left="── ${title} "
        [ -n "$title_w" ] || title_w="${#title}"
        left_w=$((2 + 1 + title_w + 1))
    else
        left="── "
        left_w=2
    fi
    n=$((cols - left_w))
    [ "$n" -lt 3 ] && n=3
    dash_add "${C_CYAN}${left}$(dash_fill "$n")${C_RESET}"
}

dash_cache_dir(){
    local base="${SBX_DASHBOARD_CACHE_DIR:-${SBX_INSTALL_DIR:-/opt/sbx}/data}"
    if mkdir -p "$base" 2>/dev/null && [ -w "$base" ]; then
        printf '%s' "$base"
        return 0
    fi
    base="${TMPDIR:-/tmp}/sbx-dashboard-${UID:-0}"
    mkdir -p "$base" 2>/dev/null || return 1
    printf '%s' "$base"
}

dash_cache_get(){
    local file="$1" key="$2"
    [ -r "$file" ] || return 1
    awk -v k="$key" '
        index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }
    ' "$file" 2>/dev/null
}

dash_cache_age(){
    local file="$1" epoch age
    [ -r "$file" ] || { echo 999999; return; }
    epoch="$(dash_cache_get "$file" epoch 2>/dev/null || true)"
    case "$epoch" in
        ''|*[!0-9]*) echo 999999; return ;;
    esac
    age=$(( $(date +%s) - epoch ))
    [ "$age" -lt 0 ] && age=0
    echo "$age"
}

dash_valid_version(){
    [[ "$1" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# GitHub is not always reachable. Prefer a direct connection, then the shared
# download proxy when one exists. All calls have short timeouts.
fetch_github_tag(){
    local url="$1" filter="$2" result
    result=$(curl -fsSL --noproxy '*' --connect-timeout 3 --max-time 8 "$url" 2>/dev/null \
        | jq -r "$filter" 2>/dev/null | sort -V | tail -n1)
    if [ -z "$result" ] && command -v setup_download_proxy >/dev/null 2>&1; then
        setup_download_proxy >/dev/null 2>&1 || true
        result=$(curl -fsSL --connect-timeout 3 --max-time 10 "$url" 2>/dev/null \
            | jq -r "$filter" 2>/dev/null | sort -V | tail -n1)
    fi
    printf '%s' "$result"
}

fetch_github_redirect_tag(){
    local url="$1" result
    result=$(curl -fsSI --noproxy '*' --connect-timeout 3 --max-time 6 "$url" 2>/dev/null \
        | sed -n 's#^[Ll]ocation: .*/tag/##p' | tr -d '\r' | head -n1)
    if [ -z "$result" ] && command -v setup_download_proxy >/dev/null 2>&1; then
        setup_download_proxy >/dev/null 2>&1 || true
        result=$(curl -fsSI --connect-timeout 3 --max-time 8 "$url" 2>/dev/null \
            | sed -n 's#^[Ll]ocation: .*/tag/##p' | tr -d '\r' | head -n1)
    fi
    printf '%s' "$result"
}

dash_spawn_version_refresh(){
    local cache="$1" dir lock age
    command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 0
    dir="$(dirname "$cache")"
    lock="$dir/version.lock"
    if [ -d "$lock" ]; then
        age=$(( $(date +%s) - $(stat -c %Y "$lock" 2>/dev/null || echo 0) ))
        [ "$age" -lt 180 ] && return 0
        rmdir "$lock" 2>/dev/null || true
    fi
    mkdir "$lock" 2>/dev/null || return 0
    (
        trap 'rmdir "$lock" 2>/dev/null || true' EXIT
        local singbox_v sbx_v tmp
        singbox_v="$(fetch_github_redirect_tag 'https://github.com/SagerNet/sing-box/releases/latest')"
        sbx_v="$(fetch_github_tag \
            'https://api.github.com/repos/driftbottle61/sbx/tags?per_page=100' \
            '.[].name | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))')"
        dash_valid_version "$singbox_v" || singbox_v=""
        dash_valid_version "$sbx_v" || sbx_v=""
        tmp="$(mktemp "$dir/.version.XXXXXX" 2>/dev/null)" || exit 0
        {
            printf 'singbox=%s\n' "$singbox_v"
            printf 'sbx=%s\n' "$sbx_v"
            printf 'epoch=%s\n' "$(date +%s)"
        } > "$tmp"
        mv "$tmp" "$cache" 2>/dev/null || rm -f "$tmp"
    ) >/dev/null 2>&1 &
}

dash_spawn_proxy_probe(){
    local cache="$1" dir lock age
    command -v curl >/dev/null 2>&1 || return 0
    dir="$(dirname "$cache")"
    lock="$dir/net.lock"
    if [ -d "$lock" ]; then
        age=$(( $(date +%s) - $(stat -c %Y "$lock" 2>/dev/null || echo 0) ))
        [ "$age" -lt 30 ] && return 0
        rmdir "$lock" 2>/dev/null || true
    fi
    mkdir "$lock" 2>/dev/null || return 0
    (
        trap 'rmdir "$lock" 2>/dev/null || true' EXIT
        local code status direct tmp
        code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 4 \
            --noproxy '' --proxy http://127.0.0.1:8080 \
            https://www.gstatic.com/generate_204 2>/dev/null)"
        if [ "$code" = "204" ]; then
            status="ok"
        else
            status="fail"
        fi
        if ping -c 1 -W 1 223.5.5.5 >/dev/null 2>&1; then
            direct="ok"
        else
            direct="fail"
        fi
        tmp="$(mktemp "$dir/.net.XXXXXX" 2>/dev/null)" || exit 0
        {
            printf 'proxy=%s\n' "$status"
            printf 'direct=%s\n' "$direct"
            printf 'epoch=%s\n' "$(date +%s)"
        } > "$tmp"
        mv "$tmp" "$cache" 2>/dev/null || rm -f "$tmp"
    ) >/dev/null 2>&1 &
}

dashboard_load_static(){
    [ "${DASHBOARD_STATIC_LOADED:-0}" = "1" ] && return 0

    DASH_HOSTNAME="$(hostname 2>/dev/null || echo unknown)"
    DASH_OS="$(grep -m1 '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d '"' -f2)"
    [ -n "$DASH_OS" ] || DASH_OS="$(uname -s 2>/dev/null || echo Linux)"
    DASH_KERNEL="$(uname -r 2>/dev/null || echo unknown)"

    local virt
    virt="$(systemd-detect-virt 2>/dev/null || echo unknown)"
    case "$virt" in
        none) DASH_VIRT="物理机" ;;
        lxc) DASH_VIRT="LXC" ;;
        kvm) DASH_VIRT="KVM" ;;
        vmware) DASH_VIRT="VMware" ;;
        microsoft) DASH_VIRT="Hyper-V" ;;
        '') DASH_VIRT="未知" ;;
        *) DASH_VIRT="$virt" ;;
    esac

    DASH_CPU_MODEL="$(lscpu 2>/dev/null | awk -F: '/Model name:/{gsub(/^[ \t]+/, "", $2); print $2; exit}')"
    [ -n "$DASH_CPU_MODEL" ] || DASH_CPU_MODEL="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//')"
    DASH_CPU_SHORT="$(printf '%s' "$DASH_CPU_MODEL" | grep -oE 'i[0-9]-[0-9]+[A-Za-z]*' | head -1)"
    [ -n "$DASH_CPU_SHORT" ] || DASH_CPU_SHORT="$(printf '%s' "$DASH_CPU_MODEL" | sed 's/  */ /g' | cut -c1-28)"
    [ -n "$DASH_CPU_SHORT" ] || DASH_CPU_SHORT="未知 CPU"
    DASH_CPU_CORE="$(nproc 2>/dev/null || echo 1)"
    DASH_MEM_TOTAL="$(free -h 2>/dev/null | awk '/Mem:/{print $2; exit}')"
    [ -n "$DASH_MEM_TOTAL" ] || DASH_MEM_TOTAL="?"

    DASHBOARD_STATIC_LOADED=1
    return 0
}

dash_uptime(){
    local raw
    raw="$(uptime -p 2>/dev/null | sed 's/^up //')"
    if [ -z "$raw" ]; then
        raw="$(awk '{
            s = int($1)
            d = int(s / 86400)
            h = int((s % 86400) / 3600)
            m = int((s % 3600) / 60)
            if (d) printf "%dd ", d
            if (h) printf "%dh ", h
            printf "%dm", m
        }' /proc/uptime 2>/dev/null)"
    fi
    printf '%s' "$raw" | sed \
        -e 's/ years\?/y/g' \
        -e 's/ weeks\?/w/g' \
        -e 's/ days\?/d/g' \
        -e 's/ hours\?/h/g' \
        -e 's/ minutes\?/m/g' \
        -e 's/ mins\?/m/g' \
        -e 's/,//g'
}

dash_singbox_pids(){
    if command -v pgrep >/dev/null 2>&1; then
        pgrep -x sing-box 2>/dev/null
    else
        ps -C sing-box -o pid= 2>/dev/null | awk '{print $1}'
    fi
}

dash_singbox_jiffies(){
    local pid total=0 value
    for pid in $(dash_singbox_pids); do
        [ -r "/proc/$pid/stat" ] || continue
        value="$(awk '{print $14 + $15}' "/proc/$pid/stat" 2>/dev/null)" || continue
        case "$value" in
            ''|*[!0-9]*) continue ;;
        esac
        total=$((total + value))
    done
    printf '%s' "$total"
}

dash_singbox_cpu(){
    local hz t1 t2 c1 c2
    hz="$(getconf CLK_TCK 2>/dev/null || echo 100)"
    case "$hz" in
        ''|*[!0-9]*) hz=100 ;;
    esac
    c1="$(dash_singbox_jiffies)"
    if [ "$c1" -eq 0 ]; then
        printf '0.0'
        return 0
    fi
    t1="$(date +%s%N)"
    sleep 0.15
    c2="$(dash_singbox_jiffies)"
    t2="$(date +%s%N)"
    awk -v c1="$c1" -v c2="$c2" -v t1="$t1" -v t2="$t2" -v hz="$hz" 'BEGIN {
        dt = (t2 - t1) / 1000000000
        dc = c2 - c1
        if (dt <= 0 || dc < 0) { printf "0.0"; exit }
        printf "%.1f", dc / hz / dt * 100
    }'
}

dash_ok(){
    if [ "$1" = "1" ]; then
        printf '%s✓%s' "$C_GREEN" "$C_RESET"
    else
        printf '%s✗%s' "$C_RED" "$C_RESET"
    fi
}

dash_feature(){
    printf '%s%s%s %s' "$C_DIM" "$1" "$C_RESET" "$(dash_ok "$2")"
}

dash_proxy_icon(){
    case "$1" in
        ok) printf '%s✓%s' "$C_GREEN" "$C_RESET" ;;
        fail) printf '%s✗%s' "$C_RED" "$C_RESET" ;;
        *) printf '%s…%s' "$C_DIM" "$C_RESET" ;;
    esac
}

dash_version_badge(){
    local current="$1" latest="$2" label="$3" newest
    if [ -z "$current" ] || [ "$current" = "未知" ]; then
        printf '%s%s 未知%s' "$C_DIM" "$label" "$C_RESET"
        return
    fi
    if [ -z "$latest" ]; then
        printf '%s%s%s %s  %s… 检查中%s' "$C_DIM" "$label" "$C_RESET" "$current" "$C_DIM" "$C_RESET"
        return
    fi
    newest="$(printf '%s\n%s\n' "${current#v}" "${latest#v}" | sort -V | tail -n1)"
    if [ "$newest" = "${current#v}" ]; then
        printf '%s%s%s %s  %s✓ 已是最新%s' "$C_DIM" "$label" "$C_RESET" "$current" "$C_GREEN" "$C_RESET"
    else
        printf '%s%s%s %s  %s↑ %s%s' "$C_DIM" "$label" "$C_RESET" "$current" "$C_YELLOW" "$latest" "$C_RESET"
    fi
}

dashboard_render(){
    local cols service enabled ip mode_label os_display
    local singbox_line sbx_line direct_status proxy_status net_age version_cache version_age need_refresh
    local v

    dashboard_init
    cols="$(dash_cols)"
    dashboard_load_static

    ip="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)"
    [ -n "$ip" ] || ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}')"
    [ -n "$ip" ] || ip="未获取"

    service="${SERVICE_NAME:-sing-box}"
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        DASH_SERVICE_LABEL="${C_GREEN}● 运行中${C_RESET}"
    else
        DASH_SERVICE_LABEL="${C_RED}● 已停止${C_RESET}"
    fi
    if systemctl is-enabled --quiet "$service" 2>/dev/null; then
        enabled=1
    else
        enabled=0
    fi

    case "${ROUTE_MODE:-tproxy}" in
        tun|TUN) mode_label="TUN" ;;
        off|OFF|none) mode_label="已关闭" ;;
        *) mode_label="TProxy" ;;
    esac

    DASH_SINGBOX_VERSION=""
    if [ -n "${SINGBOX_BIN:-}" ] && [ -x "$SINGBOX_BIN" ]; then
        DASH_SINGBOX_VERSION="$("$SINGBOX_BIN" version 2>/dev/null | head -1 | awk '{print $3}')"
        if [ -n "$DASH_SINGBOX_VERSION" ]; then
            DASH_SINGBOX_VERSION="v${DASH_SINGBOX_VERSION#v}"
        fi
    fi

    DASH_SBX_VERSION="${SBX_VERSION:-}"
    if [ -n "$DASH_SBX_VERSION" ]; then
        DASH_SBX_VERSION="v${DASH_SBX_VERSION#v}"
    fi

    DASH_CPU_PCT="$(dash_singbox_cpu)"
    DASH_RSS="$(ps -C sing-box -o rss= 2>/dev/null | awk '{s += $1} END {printf "%.0f", s / 1024}')"
    [ -n "$DASH_RSS" ] || DASH_RSS=0
    DASH_MEM_USED="$(free -h 2>/dev/null | awk '/Mem:/{print $3; exit}')"
    [ -n "$DASH_MEM_USED" ] || DASH_MEM_USED="?"
    DASH_UPTIME="$(dash_uptime)"

    DASH_CACHE_DIR="$(dash_cache_dir 2>/dev/null || true)"
    DASH_SINGBOX_LATEST=""
    DASH_SBX_LATEST=""
    direct_status=""
    proxy_status=""
    if [ -n "$DASH_CACHE_DIR" ]; then
        version_cache="$DASH_CACHE_DIR/version-cache"
        v="$(dash_cache_get "$version_cache" singbox 2>/dev/null || true)"
        if dash_valid_version "$v"; then
            DASH_SINGBOX_LATEST="$v"
        fi
        v="$(dash_cache_get "$version_cache" sbx 2>/dev/null || true)"
        if dash_valid_version "$v"; then
            DASH_SBX_LATEST="$v"
        fi

        direct_status="$(dash_cache_get "$DASH_CACHE_DIR/net-cache" direct 2>/dev/null || true)"
        proxy_status="$(dash_cache_get "$DASH_CACHE_DIR/net-cache" proxy 2>/dev/null || true)"
        net_age="$(dash_cache_age "$DASH_CACHE_DIR/net-cache")"
        if [ "$net_age" -ge 120 ]; then
            direct_status=""
            proxy_status=""
        fi

        if [ "${DASHBOARD_TTY:-0}" = "1" ] && [ "${SBX_DASHBOARD_NO_BG:-0}" != "1" ]; then
            version_age="$(dash_cache_age "$version_cache")"
            need_refresh=0
            if [ -z "$DASH_SINGBOX_LATEST" ] || [ -z "$DASH_SBX_LATEST" ]; then
                if [ "$version_age" -ge 300 ]; then
                    need_refresh=1
                fi
            fi
            if [ "$version_age" -ge 21600 ]; then
                need_refresh=1
            fi
            if [ "$need_refresh" -eq 1 ]; then
                dash_spawn_version_refresh "$version_cache"
            fi

            if [ -z "$proxy_status" ] || [ -z "$direct_status" ] || [ "$net_age" -ge 30 ]; then
                dash_spawn_proxy_probe "$DASH_CACHE_DIR/net-cache"
            fi
        fi
    fi

    if [ -c /dev/net/tun ]; then DASH_TUN=1; else DASH_TUN=0; fi
    if [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" = "1" ]; then DASH_FORWARD=1; else DASH_FORWARD=0; fi

    DASH_CLASH=0
    if command -v ss >/dev/null 2>&1; then
        if ss -lntH 2>/dev/null | awk '{print $4}' | grep -qE '[:.]9095$'; then
            DASH_CLASH=1
        elif ss -lnt 2>/dev/null | awk 'NR > 1 {print $4}' | grep -qE '[:.]9095$'; then
            DASH_CLASH=1
        fi
    fi

    if [ -f "${SBX_ZASHBOARD_INDEX:-/etc/singbox/ui/index.html}" ]; then
        DASH_ZASH=1
    else
        DASH_ZASH=0
    fi

    DASH_CONFIG=0
    if [ -n "${CONFIG_FILE:-}" ] && [ -f "$CONFIG_FILE" ]; then
        if command -v jq >/dev/null 2>&1; then
            jq empty "$CONFIG_FILE" >/dev/null 2>&1 && DASH_CONFIG=1
        else
            DASH_CONFIG=1
        fi
    fi

    if [ -n "${CONFIG_URL:-}" ]; then DASH_SUB=1; else DASH_SUB=0; fi

    if [ -n "$DASH_SBX_VERSION" ]; then
        sbx_line="$(dash_version_badge "$DASH_SBX_VERSION" "$DASH_SBX_LATEST" "SBX")"
    else
        sbx_line="${C_DIM}SBX${C_RESET} ${C_RED}未知${C_RESET}"
    fi

    if [ -n "$DASH_SINGBOX_VERSION" ]; then
        singbox_line="$(dash_version_badge "$DASH_SINGBOX_VERSION" "$DASH_SINGBOX_LATEST" "Sing-box")"
    else
        singbox_line="${C_DIM}Sing-box${C_RESET} ${C_RED}未安装${C_RESET}"
    fi

    DASH_LINES=()
    dash_rule "SBX · ${DASH_HOSTNAME} · ${ip}" "$cols"
    dash_add "${DASH_SERVICE_LABEL}   ${C_BOLD}${mode_label}${C_RESET}   ${C_DIM}直连${C_RESET} $(dash_proxy_icon "$direct_status")   ${C_DIM}代理${C_RESET} $(dash_proxy_icon "$proxy_status")   ${C_DIM}自启${C_RESET} $(dash_ok "$enabled")   ${C_DIM}运行${C_RESET} ${DASH_UPTIME}"
    dash_add "${singbox_line}    ${sbx_line}"
    dash_rule "资源" "$cols" 4
    dash_add "${C_DIM}CPU${C_RESET} ${DASH_CPU_PCT}%   ${C_DIM}RSS${C_RESET} ${DASH_RSS} MB   ${C_DIM}系统内存${C_RESET} ${DASH_MEM_USED}/${DASH_MEM_TOTAL}"
    os_display="$DASH_OS"
    if [ "${#os_display}" -gt 40 ]; then
        os_display="${os_display:0:40}…"
    fi
    dash_rule "主机" "$cols" 4
    if [ "$cols" -ge 80 ]; then
        dash_add "${os_display} ${C_DIM}·${C_RESET} 内核 ${DASH_KERNEL} ${C_DIM}·${C_RESET} ${DASH_VIRT} ${C_DIM}·${C_RESET} ${DASH_CPU_SHORT} ${C_DIM}·${C_RESET} ${DASH_CPU_CORE} 核"
    else
        dash_add "${os_display} ${C_DIM}·${C_RESET} ${DASH_VIRT}"
        dash_add "内核 ${DASH_KERNEL} ${C_DIM}·${C_RESET} ${DASH_CPU_SHORT} ${C_DIM}·${C_RESET} ${DASH_CPU_CORE} 核"
    fi
    dash_rule "网络与功能" "$cols" 10
    if [ "$cols" -ge 80 ]; then
        dash_add "$(dash_feature "TUN" "$DASH_TUN")   $(dash_feature "转发" "$DASH_FORWARD")   $(dash_feature "Clash :9095" "$DASH_CLASH")   $(dash_feature "Zashboard" "$DASH_ZASH")   $(dash_feature "配置" "$DASH_CONFIG")   $(dash_feature "订阅" "$DASH_SUB")"
    else
        dash_add "$(dash_feature "TUN" "$DASH_TUN")   $(dash_feature "转发" "$DASH_FORWARD")   $(dash_feature "Clash :9095" "$DASH_CLASH")"
        dash_add "$(dash_feature "Zashboard" "$DASH_ZASH")   $(dash_feature "配置" "$DASH_CONFIG")   $(dash_feature "订阅" "$DASH_SUB")"
    fi
    dash_rule "操作" "$cols" 4
    if [ "$cols" -ge 80 ]; then
        dash_add "  ${C_BOLD}[1]${C_RESET} 安装/升级 Sing-box    ${C_BOLD}[2]${C_RESET} 配置管理    ${C_BOLD}[3]${C_RESET} 运行管理"
        dash_add "  ${C_BOLD}[4]${C_RESET} 路由设置              ${C_BOLD}[5]${C_RESET} 工具箱      ${C_BOLD}[6]${C_RESET} Web 面板"
        dash_add "  ${C_BOLD}[7]${C_RESET} 更新 SBX 管理器       ${C_BOLD}[0]${C_RESET} 退出"
    else
        dash_add "  ${C_BOLD}[1]${C_RESET} 安装/升级 Sing-box    ${C_BOLD}[2]${C_RESET} 配置管理"
        dash_add "  ${C_BOLD}[3]${C_RESET} 运行管理              ${C_BOLD}[4]${C_RESET} 路由设置"
        dash_add "  ${C_BOLD}[5]${C_RESET} 工具箱                ${C_BOLD}[6]${C_RESET} Web 面板"
        dash_add "  ${C_BOLD}[7]${C_RESET} 更新 SBX 管理器       ${C_BOLD}[0]${C_RESET} 退出"
    fi
    dash_add ""
    return 0
}

dashboard(){
    [ "${DASHBOARD_DRAWN:-0}" = "1" ] && return 0

    if command -v load_config >/dev/null 2>&1; then
        load_config
    fi
    [ -z "${ROUTE_MODE:-}" ] && ROUTE_MODE="tproxy"

    dashboard_render

    if [ "${DASHBOARD_TTY:-0}" = "1" ]; then
        local line
        printf '\033[H'
        for line in "${DASH_LINES[@]}"; do
            printf '\033[2K%s\n' "$line"
        done
        printf '\033[J'
    else
        printf '%s\n' "${DASH_LINES[@]}"
    fi

    DASHBOARD_DRAWN=1
    return 0
}

refresh_dashboard_metrics(){
    DASHBOARD_DRAWN=0
    DASHBOARD_PROMPT_DRAWN=0
    dashboard
}
