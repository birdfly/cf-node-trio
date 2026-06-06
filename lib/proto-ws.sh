# shellcheck shell=bash
# VLESS-WS 入站 — 本地 plaintext WS，TLS 由前面那一跳 (Caddy / Cloudflared) 卸载。
# 默认 listen 127.0.0.1:10080 (只让 ingress-* 接入，不直接对外)。

proto_ws_install() {
  singbox_install

  local port uuid path
  port=${WS_PORT:-10080}
  uuid=${WS_UUID:-$(random_uuid)}
  path=${WS_PATH:-/$(random_hex 4)-ws}

  info "VLESS-WS 127.0.0.1:$port  path=$path  (TLS 由 ingress 层提供)"

  jq -n --argjson port "$port" --arg uuid "$uuid" --arg path "$path" '
  {
    type: "vless",
    tag: "vless-ws-tunnel-in",
    listen: "127.0.0.1",
    listen_port: $port,
    users: [{ uuid: $uuid }],
    transport: { type: "ws", path: $path }
  }' | singbox_add inbounds

  state_set WS_PORT "$port"
  state_set WS_UUID "$uuid"
  state_set WS_PATH "$path"
  singbox_validate_restart
  ok "VLESS-WS 已就绪，等待 ingress 层接入"
}
