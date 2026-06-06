# shellcheck shell=bash
# 内核 / 网络 调优 — BBR + 大缓冲 + 高并发. 写到 /etc/sysctl.d/, 不动 /etc/sysctl.conf.
# 幂等 — 重复跑无副作用. uninstall 时清理.

TUNE_FILE=/etc/sysctl.d/99-cf-node-trio.conf
LIMITS_FILE=/etc/security/limits.d/99-cf-node-trio.conf

tune_install() {
  info "应用网络/内核调优 …"

  # 检测能否写 sysctl (容器内常常不行, graceful 跳过)
  if ! sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1; then
    warn "当前环境不允许写 sysctl (容器?), 跳过 tune"
    return 0
  fi

  cat > "$TUNE_FILE" <<'SYSCTL'
# cf-node-trio · 网络/内核调优
# 删除本文件并 sysctl --system 即可回滚

# ── BBR + fq —— 必须搭配, 单独开 BBR 在某些内核无效 ──────────────
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# ── 连接 backlog 队列 —— 高并发短连接场景 ────────────────────────
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_local_port_range = 1024 65535

# ── TCP 缓冲到 64 MB —— 高 BDP (跨洋长连接) 上限需要够大 ─────────
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.rmem_default = 2097152
net.core.wmem_default = 2097152

# ── UDP 缓冲 —— Hysteria2 / QUIC 关键 ────────────────────────────
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

# ── TCP 行为调优 ─────────────────────────────────────────────────
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_max_orphans = 32768
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_retries2 = 8
net.ipv4.tcp_fastopen = 3

# ── VM ───────────────────────────────────────────────────────────
vm.swappiness = 10
SYSCTL

  sysctl --system >/dev/null 2>&1

  # ── 文件描述符上限 ────────────────────────────────────────────
  install -d -m 755 /etc/security/limits.d
  cat > "$LIMITS_FILE" <<'LIMITS'
# cf-node-trio · 提高 ulimit -n (sing-box 高并发要)
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
LIMITS

  # ── 验证关键项是否生效 ──────────────────────────────────────────
  local cc qd
  cc=$(sysctl -n net.ipv4.tcp_congestion_control)
  qd=$(sysctl -n net.core.default_qdisc)
  if [[ $cc == bbr && $qd == fq ]]; then
    ok "BBR + fq 已启用"
  else
    warn "BBR 未生效 (cc=$cc qd=$qd) — 内核可能 < 4.9, 升级试试"
  fi

  # 写一条状态进 state, 方便 status 显示
  state_set TUNE_APPLIED 1
}

tune_uninstall() {
  [[ -f $TUNE_FILE ]] && rm -f "$TUNE_FILE"
  [[ -f $LIMITS_FILE ]] && rm -f "$LIMITS_FILE"
  sysctl --system >/dev/null 2>&1 || true
  ok "已移除 tune 文件 (内核值需 reboot 才回滚, 或手动 sysctl 改)"
}

tune_status() {
  # sysctl 在容器/某些权限下会非零退出, 在 set -e 下会让整个函数 abort.
  # 每个读法都加 || echo "?" 保证降级到 "?" 而非中止.
  local cc qd rmem wmem som
  cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "?")
  qd=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "?")
  rmem=$(sysctl -n net.core.rmem_max 2>/dev/null || echo "0")
  wmem=$(sysctl -n net.core.wmem_max 2>/dev/null || echo "0")
  som=$(sysctl -n net.core.somaxconn 2>/dev/null || echo "?")
  printf '  TCP CC:        %s\n'  "$cc"
  printf '  qdisc:         %s\n'  "$qd"
  printf '  rmem_max:      %s (%s MB)\n' "$rmem" $((rmem/1024/1024))
  printf '  wmem_max:      %s (%s MB)\n' "$wmem" $((wmem/1024/1024))
  printf '  somaxconn:     %s\n'  "$som"
  if [[ -f $TUNE_FILE ]]; then
    printf '  tune file:     ✓ %s\n' "$TUNE_FILE"
  else
    printf '  tune file:     ✗ (未应用本脚本调优 — 跑 install.sh tune)\n'
  fi
}
