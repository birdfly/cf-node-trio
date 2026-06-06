# shellcheck shell=bash
# Hysteria2 入站 — UDP / QUIC，自带 BBR-like 拥塞控制，弱网/丢包场景常胜 TCP。
#
# 可选: 端口跳跃 (port hopping) — 把一段 UDP 端口 (HY2_PORT_RANGE) DNAT 到
# 实际的监听端口。客户端在该范围内随机切换，对运营商的"单端口大流量限速 / QoS"
# 极其有效，尤其是中国某些 ISP 在白天对单 UDP flow 限速的场景。
#
# 配置变量:
#   HY2_PORT         实际监听端口 (默认随机)
#   HY2_PORT_RANGE   "20000:40000" 形式; 留空 = 不开 hop
#   HY2_PASSWORD     口令 (默认随机 24 hex)
#   HY2_OBFS         可选 salamander 混淆口令; 留空 = 不开

proto_hy2_install() {
  singbox_install
  ensure_cmd openssl
  ensure_cmd iptables

  local port pwd obfs range crt key
  port=${HY2_PORT:-$(random_port)}
  pwd=${HY2_PASSWORD:-$(random_hex 12)}
  obfs=${HY2_OBFS:-}
  range=${HY2_PORT_RANGE:-}
  crt=/etc/sing-box/hy2.crt
  key=/etc/sing-box/hy2.key

  if [[ ! -f $crt ]]; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
      -days 3650 -nodes -subj "/CN=hy2.local" \
      -keyout "$key" -out "$crt" >/dev/null 2>&1
    chmod 600 "$key"
  fi

  info "Hysteria2 :$port (UDP)  password=${pwd:0:4}***${obfs:+  obfs=salamander}"

  # 用 jq 拼 inbound，根据 obfs 可选附加
  local inbound
  inbound=$(jq -n \
    --argjson port "$port" --arg pwd "$pwd" \
    --arg crt "$crt" --arg key "$key" --arg obfs "$obfs" \
    '
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
    }
    | if $obfs != "" then
        . + { obfs: { type: "salamander", password: $obfs } }
      else . end
    ')
  echo "$inbound" | singbox_add inbounds

  state_set HY2_PORT       "$port"
  state_set HY2_PWD        "$pwd"
  [[ -n $obfs ]] && state_set HY2_OBFS "$obfs"

  # ─── 端口跳跃: DNAT 一段范围 → 实际端口 ──────────────────────────
  if [[ -n $range ]]; then
    [[ $range =~ ^[0-9]+:[0-9]+$ ]] || die "HY2_PORT_RANGE 格式: lo:hi (如 20000:40000)"
    info "开启端口跳跃 udp $range → $port"
    _hy2_port_hop_setup "$range" "$port"
    state_set HY2_PORT_RANGE "$range"
  fi

  singbox_validate_restart

  local ip link
  ip=$(public_ipv4)
  link="hysteria2://${pwd}@${ip}:${port}"
  link+="/?insecure=1&sni=hy2.local"
  [[ -n $obfs ]] && link+="&obfs=salamander&obfs-password=${obfs}"
  [[ -n $range ]] && link+="&mport=${range/:/-}"
  link+="#hy2-direct"
  print_share_link "$link"
}

# DNAT 一段 UDP range 到实际监听端口; 持久化用 iptables-persistent 或 nft
_hy2_port_hop_setup() {
  local range=$1 port=$2 lo hi
  lo=${range%:*}; hi=${range#*:}

  # 清理同名旧规则后再加 (按 comment "cf-node-trio-hy2-hop" 识别)
  iptables -t nat -S PREROUTING 2>/dev/null \
    | grep -E '\-\-comment.*cf-node-trio-hy2-hop' \
    | sed 's/^-A/-D/' \
    | while read -r rule; do iptables -t nat $rule 2>/dev/null || true; done

  iptables -t nat -A PREROUTING -p udp --dport "$lo:$hi" \
    -j REDIRECT --to-ports "$port" \
    -m comment --comment cf-node-trio-hy2-hop

  # ip6tables 一起 (有 IPv6 才生效, 没的话 silently 失败)
  ip6tables -t nat -A PREROUTING -p udp --dport "$lo:$hi" \
    -j REDIRECT --to-ports "$port" \
    -m comment --comment cf-node-trio-hy2-hop 2>/dev/null || true

  # 持久化
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 || true
  elif command -v iptables-save >/dev/null 2>&1; then
    install -d -m 700 /etc/iptables
    iptables-save  > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
    # 系统 boot 重放
    if [[ ! -f /etc/systemd/system/cf-node-trio-iptables.service ]]; then
      cat > /etc/systemd/system/cf-node-trio-iptables.service <<'UNIT'
[Unit]
Description=cf-node-trio · restore iptables rules at boot
Before=network-pre.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c '[ -f /etc/iptables/rules.v4 ] && /sbin/iptables-restore < /etc/iptables/rules.v4; [ -f /etc/iptables/rules.v6 ] && /sbin/ip6tables-restore < /etc/iptables/rules.v6; exit 0'

[Install]
WantedBy=multi-user.target
UNIT
      systemctl enable cf-node-trio-iptables >/dev/null 2>&1 || true
    fi
  fi
}

# 卸载端口跳跃规则
_hy2_port_hop_cleanup() {
  iptables -t nat -S PREROUTING 2>/dev/null \
    | grep -E '\-\-comment.*cf-node-trio-hy2-hop' \
    | sed 's/^-A/-D/' \
    | while read -r rule; do iptables -t nat $rule 2>/dev/null || true; done
  ip6tables -t nat -S PREROUTING 2>/dev/null \
    | grep -E '\-\-comment.*cf-node-trio-hy2-hop' \
    | sed 's/^-A/-D/' \
    | while read -r rule; do ip6tables -t nat $rule 2>/dev/null || true; done
}
