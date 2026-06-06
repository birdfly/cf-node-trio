# shellcheck shell=bash
# Hysteria2 入站 — UDP / QUIC，自带 BBR-like 拥塞控制，弱网/丢包场景常胜 TCP。
# 用本地自签证书 + insecure=true 即可工作。

proto_hy2_install() {
  singbox_install
  ensure_cmd openssl

  local port pwd crt key
  port=${HY2_PORT:-$(random_port)}
  pwd=${HY2_PASSWORD:-$(random_hex 12)}
  crt=/etc/sing-box/hy2.crt
  key=/etc/sing-box/hy2.key

  if [[ ! -f $crt ]]; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
      -days 3650 -nodes -subj "/CN=hy2.local" -keyout "$key" -out "$crt" >/dev/null 2>&1
    chmod 600 "$key"
  fi

  info "Hysteria2 :$port  (UDP) password=${pwd:0:4}***"

  jq -n --argjson port "$port" --arg pwd "$pwd" --arg crt "$crt" --arg key "$key" '
  {
    type: "hysteria2",
    tag: "hy2-in",
    listen: "::",
    listen_port: $port,
    users: [{ password: $pwd }],
    tls: {
      enabled: true,
      alpn: ["h3"],
      certificate_path: $crt,
      key_path: $key
    }
  }' | singbox_add inbounds

  state_set HY2_PORT "$port"
  state_set HY2_PWD  "$pwd"
  singbox_validate_restart

  local ip link
  ip=$(public_ipv4)
  link="hysteria2://${pwd}@${ip}:${port}?insecure=1&sni=hy2.local#hy2-direct"
  print_share_link "$link"
}
