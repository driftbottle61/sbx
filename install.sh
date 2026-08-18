#!/usr/bin/env bash
set -Eeuo pipefail

readonly INSTALL_DIR="${SBX_INSTALL_DIR:-/opt/sbx}"
readonly BIN_DIR="${SBX_BIN_DIR:-/usr/local/bin}"
readonly DEFAULT_REPO="driftbottle61/sbx"
readonly DEFAULT_REF="main"

repo="${SBX_REPO:-$DEFAULT_REPO}"
ref="${SBX_REF:-$DEFAULT_REF}"
skip_deps=0
source_dir=""
work_dir=""
backup_dir=""
download_proxy_ready=0

log() { printf '[SBX] %s\n' "$*"; }
die() { printf '[SBX] ERROR: %s\n' "$*" >&2; exit 1; }

setup_download_proxy() {
    [ "$download_proxy_ready" -eq 0 ] || return 0

    local proxy="${SBX_DOWNLOAD_PROXY:-}"
    local probe_url="${SBX_PROXY_PROBE_URL:-https://www.gstatic.com/generate_204}"

    if [ "$proxy" = "off" ] || [ "$proxy" = "direct" ]; then
        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
        log "Downloads will use direct connections"
        download_proxy_ready=1
        return
    fi

    if [ -z "$proxy" ] && command -v curl >/dev/null 2>&1 \
        && curl -fsS --proxy "http://127.0.0.1:8080" \
        --connect-timeout 3 --max-time 6 "$probe_url" >/dev/null 2>&1; then
        proxy="http://127.0.0.1:8080"
    fi

    if [ -n "$proxy" ]; then
        export http_proxy="$proxy" https_proxy="$proxy"
        export HTTP_PROXY="$proxy" HTTPS_PROXY="$proxy"
        export no_proxy="${no_proxy:-127.0.0.1,localhost,::1}"
        export NO_PROXY="$no_proxy"
        log "Downloads will use proxy: $proxy"
    else
        log "No download proxy detected; using direct connections"
    fi

    download_proxy_ready=1
}

cleanup() {
    [ -z "$work_dir" ] || rm -rf "$work_dir"
}
trap cleanup EXIT

usage() {
    cat <<EOF
Usage: sudo bash install.sh [options]

Options:
  --repo OWNER/REPO  GitHub repository (default: $repo)
  --ref REF          Branch, tag, or commit (default: $ref)
  --skip-deps        Do not install operating-system dependencies
  --uninstall        Remove SBX using the installed uninstaller
  -h, --help         Show this help
EOF
}

require_root() {
    [ "${EUID:-$(id -u)}" -eq 0 ] || die "please run as root (for example: sudo bash install.sh)"
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --repo) [ "$#" -ge 2 ] || die "--repo requires a value"; repo="$2"; shift 2 ;;
            --ref) [ "$#" -ge 2 ] || die "--ref requires a value"; ref="$2"; shift 2 ;;
            --skip-deps) skip_deps=1; shift ;;
            --uninstall)
                require_root
                [ -x "$INSTALL_DIR/uninstall.sh" ] || die "SBX is not installed"
                exec "$INSTALL_DIR/uninstall.sh"
                ;;
            -h|--help) usage; exit 0 ;;
            *) die "unknown option: $1" ;;
        esac
    done
}

check_system() {
    [ -r /etc/os-release ] || die "cannot identify this operating system"
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
        debian|ubuntu) ;;
        *) die "only Debian and Ubuntu are currently supported" ;;
    esac
}

install_dependencies() {
    [ "$skip_deps" -eq 0 ] || return 0
    log "Installing required packages"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends \
        bash ca-certificates curl wget jq unzip tar iproute2 iptables nftables \
        systemd lsb-release net-tools dnsutils iputils-ping python3
}

resolve_source() {
    local script_dir archive_url archive
    script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

    if [ -f "$script_dir/sbx" ] && [ -d "$script_dir/lib" ]; then
        source_dir="$script_dir"
        return
    fi

    [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "invalid GitHub repository: $repo"
    [[ "$ref" =~ ^[A-Za-z0-9._/-]+$ ]] || die "invalid Git ref: $ref"

    work_dir="$(mktemp -d /tmp/sbx-install.XXXXXX)"
    archive="$work_dir/source.tar.gz"
    archive_url="https://github.com/$repo/archive/$ref.tar.gz"

    log "Downloading $repo ($ref)"
    setup_download_proxy
    curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
        --connect-timeout 15 --max-time "${SBX_DOWNLOAD_TIMEOUT:-300}" \
        "$archive_url" --output "$archive"
    mkdir -p "$work_dir/source"
    tar -xzf "$archive" -C "$work_dir/source" --strip-components=1
    source_dir="$work_dir/source"
    [ -f "$source_dir/sbx" ] && [ -d "$source_dir/lib" ] || die "downloaded archive is not an SBX release"
}

install_files() {
    local saved_config="" project_version

    project_version="$(sed -n 's/^SBX_VERSION="\([^"]*\)"/\1/p' "$source_dir/data/sbx.conf" | head -1)"
    [ -n "$project_version" ] || die "source package does not define SBX_VERSION"

    if [ -f "$INSTALL_DIR/data/sbx.conf" ]; then
        saved_config="$(mktemp /tmp/sbx-config.XXXXXX)"
        cp -p "$INSTALL_DIR/data/sbx.conf" "$saved_config"
    fi

    if [ -d "$INSTALL_DIR" ]; then
        backup_dir="${INSTALL_DIR}.backup.$(date +%Y%m%d%H%M%S)"
        log "Backing up existing installation to $backup_dir"
        cp -a "$INSTALL_DIR" "$backup_dir"
    fi

    mkdir -p "$INSTALL_DIR" "$INSTALL_DIR/backup" "$INSTALL_DIR/log" "$INSTALL_DIR/tmp"
    install -m 0755 "$source_dir/sbx" "$source_dir/sbx-route" \
        "$source_dir/install.sh" "$source_dir/uninstall.sh" "$INSTALL_DIR/"
    install -d -m 0755 "$INSTALL_DIR/lib" "$INSTALL_DIR/data" "$INSTALL_DIR/web"
    install -m 0644 "$source_dir"/lib/*.sh "$INSTALL_DIR/lib/"
    install -m 0644 "$source_dir/data/cn_ip.txt" "$INSTALL_DIR/data/cn_ip.txt"
    install -m 0644 "$source_dir/data/sbx-web.json.example" "$INSTALL_DIR/data/sbx-web.json.example"
    install -m 0755 "$source_dir/web/sbx_web.py" "$INSTALL_DIR/web/sbx_web.py"
    install -m 0600 "$source_dir/data/sbx.conf" "$INSTALL_DIR/data/sbx.conf"

    if [ -n "$saved_config" ]; then
        install -m 0600 "$saved_config" "$INSTALL_DIR/data/sbx.conf"
        if grep -q '^SBX_VERSION=' "$INSTALL_DIR/data/sbx.conf"; then
            sed -i "s/^SBX_VERSION=.*/SBX_VERSION=\"$project_version\"/" "$INSTALL_DIR/data/sbx.conf"
        else
            sed -i "1iSBX_VERSION=\"$project_version\"" "$INSTALL_DIR/data/sbx.conf"
        fi
        rm -f "$saved_config"
        log "Preserved existing configuration"
    fi

    ln -sfn "$INSTALL_DIR/sbx" "$BIN_DIR/sbx"
    ln -sfn "$INSTALL_DIR/sbx-route" "$BIN_DIR/sbx-route"

    # Refresh the unit on upgrades so post-start route/DNS hooks are installed
    # without requiring the user to recreate the service manually.
    if systemctl cat sing-box.service >/dev/null 2>&1 && [ -f "$INSTALL_DIR/lib/service.sh" ]; then
        # shellcheck disable=SC1091
        source "$INSTALL_DIR/lib/common.sh"
        # shellcheck disable=SC1091
        source "$INSTALL_DIR/lib/config.sh"
        # shellcheck disable=SC1091
        source "$INSTALL_DIR/lib/system.sh"
        # shellcheck disable=SC1091
        source "$INSTALL_DIR/lib/service.sh"
        create_service
    fi
}

verify_installation() {
    bash -n "$INSTALL_DIR/sbx" "$INSTALL_DIR/sbx-route" "$INSTALL_DIR"/lib/*.sh
    python3 -m py_compile "$INSTALL_DIR/web/sbx_web.py"
    [ -x "$BIN_DIR/sbx" ] || die "command link was not created"
}

main() {
    parse_args "$@"
    require_root
    check_system
    setup_download_proxy
    install_dependencies
    resolve_source
    install_files
    verify_installation

    log "Installation complete"
    log "Run: sbx"
    [ -z "$backup_dir" ] || log "Previous installation backup: $backup_dir"
}

main "$@"
