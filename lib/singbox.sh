# shellcheck shell=bash
# sing-box 安装 + systemd unit

singbox_install() {
  if command -v sing-box >/dev/null 2>&1; then
    log "sing-box 已存在: $(sing-box version | head -1)"
    return 0
  fi
  info "下载并安装 sing-box ($ARCH_TAG) …"
  ensure_cmd jq
  ensure_cmd curl
  ensure_cmd tar

  local ver url tmp
  ver=$(curl -fsS https://api.github.com/repos/SagerNet/sing-box/releases/latest \
        | jq -r '.tag_name')
  [[ -n $ver && $ver != null ]] || die "无法获取 sing-box 最新版本"
  ver=${ver#v}
  url="https://github.com/SagerNet/sing-box/releases/download/v${ver}/sing-box-${ver}-linux-${ARCH_TAG}.tar.gz"
  tmp=$(mktemp -d)
  curl -fsSL "$url" | tar -xz -C "$tmp" --strip-components=1
  install -m 755 "$tmp/sing-box" /usr/local/bin/sing-box
  rm -rf "$tmp"
  ok "sing-box v$ver 装好"

  install -d -m 700 /etc/sing-box
  cat > /etc/systemd/system/sing-box.service <<'UNIT'
[Unit]
Description=sing-box
After=network.target nss-lookup.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable sing-box >/dev/null 2>&1
  ok "sing-box.service 已注册"
}
