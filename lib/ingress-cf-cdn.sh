# shellcheck shell=bash
# 入口 1: CF CDN 反代 (Caddy 自动 TLS)
#
#   client ─→ CF CDN (TLS)  ─→ Caddy:443 (TLS 再卸一次) ─→ sing-box VLESS-WS:10080
#
# 要求:
#   (a) 域名已在 Cloudflare 接管 (NS 已指向 CF)
#   (b) 已为子域加 A 记录指向 VPS 公网 IP, 橙云开启
#   (c) VLESS-WS 入站已装 (proto_ws_install)

ingress_cf_cdn_install() {
  local domain port path
  domain=${CF_CDN_DOMAIN:?需设置 CF_CDN_DOMAIN=cdn.your.domain}

  port=$(state_get WS_PORT) || die "请先安装 VLESS-WS 入站"
  path=$(state_get WS_PATH) || die "请先安装 VLESS-WS 入站"

  ensure_cmd curl
  if ! command -v caddy >/dev/null 2>&1; then
    info "装 Caddy …"
    apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl >/dev/null
    curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key \
      | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt \
      > /etc/apt/sources.list.d/caddy-stable.list
    apt-get update -qq && apt-get install -y -qq caddy >/dev/null
  fi

  info "写 Caddyfile 块 → $domain"
  local block="
# ── cf-node-trio: CF CDN 反代 ──
$domain {
    encode zstd gzip
    # 把 WS 帧透传到本地 sing-box
    @ws {
        header Connection *Upgrade*
        header Upgrade websocket
        path $path
    }
    reverse_proxy @ws 127.0.0.1:$port {
        header_up X-Real-IP {http.request.remote.host}
    }
    # 其他请求返回 200 OK 做伪装
    respond \"It works.\" 200
}
"
  if grep -q "^$domain {" /etc/caddy/Caddyfile 2>/dev/null; then
    warn "Caddyfile 已包含 $domain — 跳过 (手动删 cf-node-trio 块再重跑)"
  else
    echo "$block" >> /etc/caddy/Caddyfile
    caddy validate --config /etc/caddy/Caddyfile >/dev/null || die "Caddyfile 校验失败"
    systemctl reload caddy
    ok "Caddy 已 reload"
  fi

  local uuid link
  uuid=$(state_get WS_UUID)
  link="vless://${uuid}@${domain}:443?security=tls&encryption=none&type=ws&path=$(printf %s "$path" | jq -sRr @uri)&host=${domain}&sni=${domain}#cf-cdn"
  state_set CF_CDN_DOMAIN "$domain"
  print_share_link "$link"
}
