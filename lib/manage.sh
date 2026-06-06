# shellcheck shell=bash
# manage 子命令: 查看状态 / 输出订阅 / 改端口 / QR

# ─── 构造单个协议的 share link ─────────────────────────────────────────
_link_reality() {
  local uuid port sni pub sid ip
  uuid=$(state_get REALITY_UUID) || return 1
  port=$(state_get REALITY_PORT)
  sni=$(state_get REALITY_SNI)
  pub=$(state_get REALITY_PUB)
  sid=$(state_get REALITY_SID)
  ip=$(public_ipv4)
  printf 'vless://%s@%s:%s?security=reality&encryption=none&flow=xtls-rprx-vision&type=tcp&sni=%s&fp=chrome&pbk=%s&sid=%s#reality-direct\n' \
    "$uuid" "$ip" "$port" "$sni" "$pub" "$sid"
}

_link_hy2() {
  local pwd port obfs range ip link
  pwd=$(state_get HY2_PWD) || return 1
  port=$(state_get HY2_PORT)
  obfs=$(state_get HY2_OBFS 2>/dev/null || echo "")
  range=$(state_get HY2_PORT_RANGE 2>/dev/null || echo "")
  ip=$(public_ipv4)
  link="hysteria2://${pwd}@${ip}:${port}/?insecure=1&sni=hy2.local"
  [[ -n $obfs ]] && link+="&obfs=salamander&obfs-password=${obfs}"
  [[ -n $range ]] && link+="&mport=${range/:/-}"
  printf '%s#hy2-direct\n' "$link"
}

_link_anytls() {
  local pwd port ip
  pwd=$(state_get ANYTLS_PWD) || return 1
  port=$(state_get ANYTLS_PORT)
  ip=$(public_ipv4)
  printf 'anytls://%s@%s:%s?insecure=1&sni=anytls.local#anytls-direct\n' \
    "$pwd" "$ip" "$port"
}

_link_ws_via() {
  # _link_ws_via <host> <tag>
  local host=$1 tag=$2 uuid path
  uuid=$(state_get WS_UUID) || return 1
  path=$(state_get WS_PATH)
  local pathenc
  pathenc=$(printf %s "$path" | jq -sRr @uri)
  printf 'vless://%s@%s:443?security=tls&encryption=none&type=ws&path=%s&host=%s&sni=%s#%s\n' \
    "$uuid" "$host" "$pathenc" "$host" "$host" "$tag"
}

# ─── 输出所有已部署的 share links ──────────────────────────────────────
cmd_subscribe() {
  local format=${1:-plain}     # plain | base64 | clash-snippet
  local lines=()

  _link_reality 2>/dev/null && lines+=("$(_link_reality)")
  _link_hy2     2>/dev/null && lines+=("$(_link_hy2)")
  _link_anytls  2>/dev/null && lines+=("$(_link_anytls)")

  local host
  host=$(state_get CF_CDN_DOMAIN 2>/dev/null) && \
    lines+=("$(_link_ws_via "$host" cf-cdn)")
  host=$(state_get ARGO_HOST 2>/dev/null) && \
    lines+=("$(_link_ws_via "$host" cf-argo-temp)")
  host=$(state_get TUNNEL_DOMAIN 2>/dev/null) && \
    lines+=("$(_link_ws_via "$host" cf-named-tunnel)")

  [[ ${#lines[@]} -gt 0 ]] || { warn "没有已部署节点 — 先跑 install.sh"; return 1; }

  case $format in
    plain)
      printf '%s\n' "${lines[@]}"
      ;;
    base64)
      printf '%s\n' "${lines[@]}" | base64 -w0
      echo
      ;;
    *)
      die "未知格式: $format (支持: plain | base64)"
      ;;
  esac
}

# ─── QR (qrencode 优先, fallback 在线服务) ─────────────────────────────
cmd_qr() {
  local target=$1
  [[ -n $target ]] || die "用法: manage qr <reality|hy2|anytls|cf-cdn|argo|tunnel|all>"

  local out=()
  case $target in
    reality)  out+=("$(_link_reality)") ;;
    hy2)      out+=("$(_link_hy2)") ;;
    anytls)   out+=("$(_link_anytls)") ;;
    cf-cdn)   out+=("$(_link_ws_via "$(state_get CF_CDN_DOMAIN)" cf-cdn)") ;;
    argo)     out+=("$(_link_ws_via "$(state_get ARGO_HOST)" cf-argo-temp)") ;;
    tunnel)   out+=("$(_link_ws_via "$(state_get TUNNEL_DOMAIN)" cf-named-tunnel)") ;;
    all)
      mapfile -t out < <(cmd_subscribe plain)
      ;;
    *) die "未知 target: $target" ;;
  esac

  if command -v qrencode >/dev/null 2>&1; then
    for link in "${out[@]}"; do
      [[ -z $link ]] && continue
      printf '\n%s\n' "$link"
      qrencode -t ANSIUTF8 "$link"
    done
  else
    warn "未装 qrencode, 显示 URL only (apt install qrencode)"
    printf '%s\n' "${out[@]}"
  fi
}

# ─── status: 整体一览 ──────────────────────────────────────────────────
cmd_status() {
  printf '%s═══ cf-node-trio · 状态 ═══%s\n' "$C_BLU" "$C_RST"

  # 协议入站
  if [[ -f /etc/sing-box/config.json ]]; then
    echo
    echo "${C_GRN}协议入站 (sing-box)${C_RST}:"
    jq -r '.inbounds[] | "  - \(.tag // "?")  \(.type)  port=\(.listen_port // "?")"' \
       /etc/sing-box/config.json 2>/dev/null
    systemctl is-active --quiet sing-box \
      && echo "  service: ${C_GRN}active${C_RST}" \
      || echo "  service: ${C_RED}inactive${C_RST}"
  fi

  # CF 接入
  echo
  echo "${C_GRN}CF 接入${C_RST}:"
  local h
  h=$(state_get CF_CDN_DOMAIN 2>/dev/null) && \
    echo "  ✓ CF CDN 反代:    $h" || echo "  ✗ CF CDN 反代:    (未配)"
  h=$(state_get ARGO_HOST 2>/dev/null) && \
    echo "  ✓ Argo 临时:      $h" || echo "  ✗ Argo 临时:      (未配)"
  h=$(state_get TUNNEL_DOMAIN 2>/dev/null) && \
    echo "  ✓ Named Tunnel:   $h" || echo "  ✗ Named Tunnel:   (未配)"

  # 内核调优
  echo
  echo "${C_GRN}内核 / 网络${C_RST}:"
  if declare -f tune_status >/dev/null; then
    tune_status
  fi

  echo
  echo "${C_DIM}用 'subscribe' 看链接, 'qr all' 看 QR, 'tune' 应用 BBR + 调优${C_RST}"
}

# ─── port 修改 ────────────────────────────────────────────────────────
cmd_port() {
  local proto=$1 newport=$2
  [[ -n $proto && -n $newport ]] || die "用法: manage port <reality|hy2|anytls|ws> <newport>"
  [[ $newport =~ ^[0-9]+$ ]] || die "端口必须是数字"

  local section=inbounds tag oldport
  case $proto in
    reality)  tag=vless-reality-in    ; oldport=$(state_get REALITY_PORT) ;;
    hy2)      tag=hy2-in               ; oldport=$(state_get HY2_PORT) ;;
    anytls)   tag=anytls-in            ; oldport=$(state_get ANYTLS_PORT) ;;
    ws)       tag=vless-ws-tunnel-in   ; oldport=$(state_get WS_PORT) ;;
    *) die "未知协议: $proto" ;;
  esac

  info "改 $proto 端口: $oldport → $newport"

  local tmp=$(mktemp)
  jq --arg tag "$tag" --argjson p "$newport" '
    (.inbounds[] | select(.tag == $tag) | .listen_port) = $p
  ' /etc/sing-box/config.json > "$tmp" && mv "$tmp" /etc/sing-box/config.json

  case $proto in
    reality) state_set REALITY_PORT "$newport" ;;
    hy2)     state_set HY2_PORT "$newport" ;;
    anytls)  state_set ANYTLS_PORT "$newport" ;;
    ws)      state_set WS_PORT "$newport" ;;
  esac

  singbox_validate_restart
  ok "$proto 现在监听 $newport"
}
