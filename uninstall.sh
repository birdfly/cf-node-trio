#!/usr/bin/env bash
# cf-node-trio · 卸载
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/lib/common.sh"
require_root

info "停止 systemd 服务 …"
for svc in sing-box cf-argo cf-named-tunnel cf-node-trio-iptables; do
  systemctl disable --now "$svc" 2>/dev/null || true
  rm -f "/etc/systemd/system/${svc}.service"
done
systemctl daemon-reload

info "清理 Hysteria2 端口跳跃 iptables 规则 …"
. "$HERE/lib/proto-hy2.sh"
_hy2_port_hop_cleanup 2>/dev/null || true

info "清理 Caddyfile 块 (注释标记内的) …"
if [[ -f /etc/caddy/Caddyfile ]]; then
  # 删除 "# ── cf-node-trio:" 起 直到下一个 "# ──" 或文件尾
  awk '
    /^# ── cf-node-trio:/{skip=1; next}
    skip && /^# ──/ && !/^# ── cf-node-trio:/{skip=0}
    !skip
  ' /etc/caddy/Caddyfile > /etc/caddy/Caddyfile.new
  mv /etc/caddy/Caddyfile.new /etc/caddy/Caddyfile
  systemctl reload caddy 2>/dev/null || true
fi

info "保留 /usr/local/bin/{sing-box,cloudflared,caddy}, 配置移到备份"
ts=$(date +%Y%m%d-%H%M%S)
bak=/root/cf-node-trio-uninstall-$ts
mkdir -p "$bak"
mv /etc/sing-box     "$bak/" 2>/dev/null || true
mv /etc/cloudflared  "$bak/" 2>/dev/null || true
mv /etc/cf-node-trio "$bak/" 2>/dev/null || true

ok "已卸载 — 备份在 $bak"
