# shellcheck shell=bash
# 入口 3: CF Named Tunnel (Argo 永久隧道)
#
#   client ─→ <subdomain>.your.domain ─→ CF Edge ─→ cloudflared(凭证) ─→ sing-box VLESS-WS:10080
#
# 流程：
#   1. 本地 `cloudflared tunnel login` 拿到 cert.pem（在你机器上做一次）
#   2. 本脚本: `cloudflared tunnel create <name>` 拿到 <uuid>.json
#   3. 写 /etc/cloudflared/config.yml + 注册 DNS route
#   4. systemd 起 cloudflared run
#
# 复用现有凭证: 把 cert.pem 放 /root/.cloudflared/cert.pem 再跑本脚本。

ingress_tunnel_install() {
  local domain name
  domain=${TUNNEL_DOMAIN:?需设置 TUNNEL_DOMAIN=node.your.domain (须在你 CF 账号下)}
  name=${TUNNEL_NAME:-cf-node-trio}

  local port path uuid
  port=$(state_get WS_PORT) || die "请先安装 VLESS-WS 入站"
  path=$(state_get WS_PATH) || die "请先安装 VLESS-WS 入站"
  uuid=$(state_get WS_UUID)

  . "$(dirname "${BASH_SOURCE[0]}")/ingress-argo.sh"   # 复用 cloudflared 安装
  cloudflared_install_bin

  if [[ ! -f /root/.cloudflared/cert.pem ]]; then
    cat <<EOF >&2
${C_YEL}!${C_RST} 缺少 /root/.cloudflared/cert.pem
请在你本地机器上跑:  cloudflared tunnel login
浏览器授权后会下载 cert.pem, scp 上来:
    scp ~/.cloudflared/cert.pem root@<this-vps>:/root/.cloudflared/cert.pem
然后重新跑本脚本.
EOF
    exit 1
  fi

  install -d -m 700 /etc/cloudflared

  # 复用同名 tunnel 若已存在
  local tunnel_id
  tunnel_id=$(cloudflared tunnel list --output json 2>/dev/null \
              | jq -r --arg n "$name" '.[] | select(.name==$n) | .id' \
              | head -1)
  if [[ -z $tunnel_id ]]; then
    info "创建 tunnel: $name"
    cloudflared tunnel create "$name" >/dev/null
    tunnel_id=$(cloudflared tunnel list --output json \
                | jq -r --arg n "$name" '.[] | select(.name==$n) | .id' | head -1)
  fi
  [[ -n $tunnel_id ]] || die "无法创建/找到 tunnel"

  # 拷凭证到 /etc/cloudflared/
  cp -f "/root/.cloudflared/${tunnel_id}.json" "/etc/cloudflared/${tunnel_id}.json"

  cat > /etc/cloudflared/config.yml <<YAML
tunnel: $tunnel_id
credentials-file: /etc/cloudflared/${tunnel_id}.json
no-autoupdate: true
ingress:
  - hostname: $domain
    service: http://127.0.0.1:$port
    originRequest:
      noTLSVerify: true
  - service: http_status:404
YAML

  info "为 $domain 注册 DNS route → tunnel $tunnel_id"
  cloudflared tunnel route dns -f "$tunnel_id" "$domain" >/dev/null

  cat > /etc/systemd/system/cf-named-tunnel.service <<UNIT
[Unit]
Description=cf-node-trio · Named Tunnel
After=network.target

[Service]
ExecStart=/usr/local/bin/cloudflared tunnel --no-autoupdate --config /etc/cloudflared/config.yml run
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable --now cf-named-tunnel >/dev/null
  sleep 2
  systemctl is-active --quiet cf-named-tunnel || die "cf-named-tunnel 启动失败"

  state_set TUNNEL_DOMAIN "$domain"
  state_set TUNNEL_ID     "$tunnel_id"

  local link
  link="vless://${uuid}@${domain}:443?security=tls&encryption=none&type=ws&path=$(printf %s "$path" | jq -sRr @uri)&host=${domain}&sni=${domain}#cf-named-tunnel"
  print_share_link "$link"
}
