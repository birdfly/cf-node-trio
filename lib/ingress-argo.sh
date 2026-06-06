# shellcheck shell=bash
# 入口 2: CF Argo 临时隧道 (Quick Tunnel)
#
#   client ─→ <random>.trycloudflare.com ─→ CF Edge ─→ cloudflared ─→ sing-box VLESS-WS:10080
#
# 不需要域名、不需要 CF 账号；缺点是子域随机、不能复用、长时不稳定。
# 适合临时性 / 一次性测试。

ingress_argo_install() {
  local port path uuid
  port=$(state_get WS_PORT) || die "请先安装 VLESS-WS 入站"
  path=$(state_get WS_PATH) || die "请先安装 VLESS-WS 入站"
  uuid=$(state_get WS_UUID)

  cloudflared_install_bin

  cat > /etc/systemd/system/cf-argo.service <<UNIT
[Unit]
Description=cf-node-trio · Argo (Quick Tunnel)
After=network.target

[Service]
ExecStart=/usr/local/bin/cloudflared tunnel --no-autoupdate --url http://127.0.0.1:$port
Restart=on-failure
RestartSec=5
StandardOutput=append:/var/log/cf-argo.log
StandardError=append:/var/log/cf-argo.log

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable --now cf-argo >/dev/null

  info "等待 cloudflared 分配 trycloudflare.com 子域 …"
  local host="" i
  for i in {1..30}; do
    host=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /var/log/cf-argo.log 2>/dev/null | head -1 | sed 's|https://||')
    [[ -n $host ]] && break
    sleep 1
  done
  [[ -n $host ]] || die "30s 内未拿到 trycloudflare 子域 — 检查 /var/log/cf-argo.log"

  state_set ARGO_HOST "$host"

  local link
  link="vless://${uuid}@${host}:443?security=tls&encryption=none&type=ws&path=$(printf %s "$path" | jq -sRr @uri)&host=${host}&sni=${host}#cf-argo-temp"
  print_share_link "$link"
}

cloudflared_install_bin() {
  command -v cloudflared >/dev/null 2>&1 && return 0
  info "装 cloudflared …"
  local url
  case $ARCH_TAG in
    amd64) url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" ;;
    arm64) url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" ;;
  esac
  curl -fsSL -o /usr/local/bin/cloudflared "$url"
  chmod +x /usr/local/bin/cloudflared
  ok "cloudflared $(cloudflared --version 2>&1 | head -1)"
}
