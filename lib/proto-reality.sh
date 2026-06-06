# shellcheck shell=bash
# VLESS-Reality 入站 — 直连，不经 CF。
# 借伪装站点的 TLS 证书做 SNI，握手后由 sing-box 解密 VLESS 流量。

proto_reality_install() {
  singbox_install
  ensure_cmd openssl

  local port uuid sni keypair pri pub sid
  port=${REALITY_PORT:-$(random_port)}
  uuid=${REALITY_UUID:-$(random_uuid)}
  sni=${REALITY_SNI:-www.cloudflare.com}
  # generate x25519
  keypair=$(/usr/local/bin/sing-box generate reality-keypair)
  pri=$(awk -F': *' '/PrivateKey/{print $2}' <<<"$keypair")
  pub=$(awk -F': *' '/PublicKey/{print $2}'  <<<"$keypair")
  sid=$(random_hex 4)

  info "VLESS-Reality :$port  SNI=$sni"

  jq -n --argjson port "$port" --arg uuid "$uuid" \
        --arg sni "$sni" --arg pri "$pri" --arg sid "$sid" '
  {
    type: "vless",
    tag: "vless-reality-in",
    listen: "::",
    listen_port: $port,
    users: [{ uuid: $uuid, flow: "xtls-rprx-vision" }],
    tls: {
      enabled: true,
      server_name: $sni,
      reality: {
        enabled: true,
        handshake: { server: $sni, server_port: 443 },
        private_key: $pri,
        short_id: [$sid]
      }
    }
  }' | singbox_add inbounds

  state_set REALITY_PORT  "$port"
  state_set REALITY_UUID  "$uuid"
  state_set REALITY_SNI   "$sni"
  state_set REALITY_PUB   "$pub"
  state_set REALITY_SID   "$sid"
  singbox_validate_restart

  local ip link
  ip=$(public_ipv4)
  link="vless://${uuid}@${ip}:${port}?security=reality&encryption=none&flow=xtls-rprx-vision&type=tcp&sni=${sni}&fp=chrome&pbk=${pub}&sid=${sid}#reality-direct"
  print_share_link "$link"
}
