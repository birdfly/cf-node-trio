# shellcheck shell=bash
# cf-node-trio · 通用函数
# 全部 lib/*.sh 都 source 它。POSIX 友好风格 + bash 4+。

set -o pipefail
umask 077

# ─── 颜色 / 日志 ────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_BLU=$'\033[34m'; C_DIM=$'\033[2m';  C_RST=$'\033[0m'
else
  C_RED= C_GRN= C_YEL= C_BLU= C_DIM= C_RST=
fi

log()  { printf '%s[%s]%s %s\n' "$C_DIM" "$(date +%H:%M:%S)" "$C_RST" "$*"; }
info() { printf '%s▸%s %s\n' "$C_BLU" "$C_RST" "$*"; }
ok()   { printf '%s✓%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn() { printf '%s!%s %s\n' "$C_YEL" "$C_RST" "$*" >&2; }
die()  { printf '%s✗%s %s\n' "$C_RED" "$C_RST" "$*" >&2; exit 1; }

# ─── 前置检查 ───────────────────────────────────────────────────────────
require_root() {
  [[ $EUID -eq 0 ]] || die "需要 root 权限 (sudo bash $0 ...)"
}

detect_os() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID=${ID:-unknown}
    OS_VER=${VERSION_ID:-unknown}
  else
    OS_ID=unknown OS_VER=unknown
  fi
  case $OS_ID in
    ubuntu|debian) PKG=apt ;;
    centos|rhel|fedora|rocky|almalinux) PKG=dnf ;;
    *) PKG="" ;;
  esac
  ARCH=$(uname -m)
  case $ARCH in
    x86_64|amd64) ARCH_TAG=amd64 ;;
    aarch64|arm64) ARCH_TAG=arm64 ;;
    *) die "不支持的架构: $ARCH" ;;
  esac
  log "OS=$OS_ID/$OS_VER  ARCH=$ARCH_TAG  PKG=${PKG:-?}"
}

ensure_cmd() {
  # ensure_cmd <cmd> [<apt-pkg>]
  local cmd=$1 pkg=${2:-$1}
  command -v "$cmd" >/dev/null 2>&1 && return 0
  case $PKG in
    apt) DEBIAN_FRONTEND=noninteractive apt-get update -qq &&
         DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg" >/dev/null ;;
    dnf) dnf install -y -q "$pkg" >/dev/null ;;
    *)   die "未知包管理器，请手动安装: $cmd" ;;
  esac
  command -v "$cmd" >/dev/null 2>&1 || die "$cmd 安装失败"
}

# ─── 工具 ──────────────────────────────────────────────────────────────
random_port()  { shuf -i 20000-50000 -n 1; }
random_uuid()  { cat /proc/sys/kernel/random/uuid; }
random_hex()   { local n=${1:-16}; head -c "$n" /dev/urandom | xxd -p -c"$n"; }

public_ipv4() {
  curl -fsS4 --max-time 5 https://api.ipify.org || \
  curl -fsS4 --max-time 5 https://ifconfig.me   || echo ""
}

# ─── 配置 / 状态目录 ────────────────────────────────────────────────────
CFG_ROOT=${CFG_ROOT:-/etc/cf-node-trio}
STATE_FILE=$CFG_ROOT/state.env

ensure_cfg_dir() { mkdir -p "$CFG_ROOT"; }

state_set() {
  # state_set KEY VALUE
  ensure_cfg_dir
  local k=$1 v=$2 tmp
  tmp=$(mktemp)
  if [[ -f $STATE_FILE ]]; then
    grep -v "^${k}=" "$STATE_FILE" > "$tmp" || true
  fi
  printf '%s=%q\n' "$k" "$v" >> "$tmp"
  mv "$tmp" "$STATE_FILE"
  chmod 600 "$STATE_FILE"
}

state_get() {
  [[ -f $STATE_FILE ]] || return 1
  # shellcheck disable=SC1090
  ( . "$STATE_FILE"; eval "printf '%s' \"\$$1\"" )
}

# ─── sing-box 配置合并 ──────────────────────────────────────────────────
# 用 jq 把 {inbound|outbound} JSON 片段合并进 /etc/sing-box/config.json
# 输入: stdin = JSON 片段，1 个参数 = "inbounds" 或 "outbounds"
singbox_add() {
  local section=$1
  local cfg=/etc/sing-box/config.json frag tmp
  frag=$(cat)
  tmp=$(mktemp)
  if [[ ! -f $cfg ]]; then
    echo '{"log":{"level":"info"},"inbounds":[],"outbounds":[{"type":"direct","tag":"direct"}]}' > "$cfg"
  fi
  # 按 tag 去重: 同名 tag 先删, 再 append
  local tag
  tag=$(echo "$frag" | jq -r '.tag // empty')
  jq --arg sec "$section" --arg tag "$tag" --argjson frag "$frag" '
    .[$sec] = ((.[$sec] // []) | map(select(.tag != $tag)) + [$frag])
  ' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
  chmod 600 "$cfg"
}

singbox_validate_restart() {
  /usr/local/bin/sing-box check -c /etc/sing-box/config.json ||
    die "sing-box config 校验失败 — 请检查 $cfg"
  systemctl restart sing-box
  sleep 1
  systemctl is-active --quiet sing-box || die "sing-box 启动失败"
  ok "sing-box 重启 OK"
}

# ─── 输出节点信息 ──────────────────────────────────────────────────────
print_share_link() {
  printf '\n%s════════════════════════════════════════════════════%s\n' "$C_GRN" "$C_RST"
  printf '%s 节点已就绪 / Node ready:%s\n\n' "$C_GRN" "$C_RST"
  printf '%s\n' "$1"
  printf '\n%s════════════════════════════════════════════════════%s\n\n' "$C_GRN" "$C_RST"
}
