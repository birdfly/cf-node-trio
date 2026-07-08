# shellcheck shell=bash
# AnyTLS 入站 — 基于 TLS 的多路复用代理，sing-box 1.10+ 支持。
#   ANYTLS_DOMAIN 留空 = 自签证书 (客户端需 insecure=1，一眼假)
#   ANYTLS_DOMAIN 填域名 (需已解析到本机) = sing-box ACME 自动签 Let's Encrypt 真证书
#     真证书才能让 AnyTLS 看起来像普通 HTTPS 站点，抗探测能力天差地别。
#     ACME 走 HTTP-01，需 :80 对公网可达 (仅签发/续期时短暂用到)。

proto_anytls_install() {
  singbox_install

  local port pwd domain tls_json
  port=${ANYTLS_PORT:-$(random_port)}
  pwd=${ANYTLS_PASSWORD:-$(random_hex 12)}
  domain=${ANYTLS_DOMAIN:-}

  if [[ -n $domain ]]; then
    local email=${ANYTLS_ACME_EMAIL:-admin@$domain}
    info "AnyTLS :$port  password=${pwd:0:4}***  (ACME 真证书: $domain, 需 :80 可达)"
    tls_json=$(jq -n --arg sni "$domain" --arg email "$email" '
      { enabled: true, server_name: $sni,
        acme: { domain: [$sni], email: $email,
                data_directory: "/etc/sing-box/acme",
                disable_tls_alpn_challenge: true } }')
  else
    ensure_cmd openssl
    local crt=/etc/sing-box/anytls.crt key=/etc/sing-box/anytls.key
    if [[ ! -f $crt ]]; then
      openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -days 3650 -nodes -subj "/CN=anytls.local" -keyout "$key" -out "$crt" >/dev/null 2>&1
      chmod 600 "$key"
    fi
    info "AnyTLS :$port  password=${pwd:0:4}***  (自签证书，客户端需 insecure=1)"
    tls_json=$(jq -n --arg crt "$crt" --arg key "$key" '
      { enabled: true, certificate_path: $crt, key_path: $key }')
  fi

  jq -n --argjson port "$port" --arg pwd "$pwd" --argjson tls "$tls_json" '
  {
    type: "anytls",
    tag: "anytls-in",
    listen: "::",
    listen_port: $port,
    users: [{ password: $pwd }],
    tls: $tls
  }' | singbox_add inbounds

  state_set ANYTLS_PORT "$port"
  state_set ANYTLS_PWD  "$pwd"
  [[ -n $domain ]] && state_set ANYTLS_DOMAIN "$domain"
  singbox_validate_restart

  local ip link
  if [[ -n $domain ]]; then
    link="anytls://${pwd}@${domain}:${port}?sni=${domain}#anytls-direct"
  else
    ip=$(public_ipv4)
    link="anytls://${pwd}@${ip}:${port}?insecure=1&sni=anytls.local#anytls-direct"
  fi
  print_share_link "$link"
}
