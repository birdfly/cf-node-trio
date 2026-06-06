# shellcheck shell=bash
# AnyTLS 入站 — 基于 TLS 的多路复用代理，sing-box 1.10+ 支持。

proto_anytls_install() {
  singbox_install
  ensure_cmd openssl

  local port pwd crt key
  port=${ANYTLS_PORT:-$(random_port)}
  pwd=${ANYTLS_PASSWORD:-$(random_hex 12)}
  crt=/etc/sing-box/anytls.crt
  key=/etc/sing-box/anytls.key

  if [[ ! -f $crt ]]; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
      -days 3650 -nodes -subj "/CN=anytls.local" -keyout "$key" -out "$crt" >/dev/null 2>&1
    chmod 600 "$key"
  fi

  info "AnyTLS :$port  password=${pwd:0:4}***"

  jq -n --argjson port "$port" --arg pwd "$pwd" --arg crt "$crt" --arg key "$key" '
  {
    type: "anytls",
    tag: "anytls-in",
    listen: "::",
    listen_port: $port,
    users: [{ password: $pwd }],
    tls: {
      enabled: true,
      certificate_path: $crt,
      key_path: $key
    }
  }' | singbox_add inbounds

  state_set ANYTLS_PORT "$port"
  state_set ANYTLS_PWD  "$pwd"
  singbox_validate_restart

  local ip link
  ip=$(public_ipv4)
  link="anytls://${pwd}@${ip}:${port}?insecure=1&sni=anytls.local#anytls-direct"
  print_share_link "$link"
}
