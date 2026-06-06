#!/usr/bin/env bash
# 容器里跑的实际测试脚本
set -e
cd /work
apt-get update -qq
apt-get install -y -qq jq curl iputils-ping iptables qrencode ca-certificates xxd >/dev/null

echo
echo "════ 1) install.sh --help ════"
bash install.sh --help | head -25

echo
echo "════ 2) lib/*.sh all source cleanly ════"
for f in lib/*.sh; do
  bash -c ". $f && echo \"  ok $f\""
done

echo
echo "════ 3) install.sh status (空状态) ════"
bash install.sh status 2>&1 | head -20

echo
echo "════ 4) 装 sing-box (跳过 systemctl/restart) ════"
. lib/common.sh
. lib/singbox.sh
. lib/proto-ws.sh
detect_os
# mock systemctl + restart in container
systemctl() { echo "  [mock systemctl $*]"; }
export -f systemctl
singbox_validate_restart() {
  /usr/local/bin/sing-box check -c /etc/sing-box/config.json && echo "  ✓ config valid"
}
export -f singbox_validate_restart
WS_PORT=10080 WS_UUID=00000000-0000-0000-0000-000000000001 WS_PATH=/test-ws \
  proto_ws_install

echo
echo "════ 5) config.json content ════"
jq '.inbounds[] | {tag, type, listen, listen_port}' /etc/sing-box/config.json

echo
echo "════ 6) manage subscribe (空 -- 因为 state 没 reality/hy2 等) ════"
bash install.sh subscribe plain 2>&1 || true

echo
echo "════ 7) bench/speedtest.sh --help ════"
bash bench/speedtest.sh --help | head -10

echo
echo "════ 8) docs/protocols.md 含 port hopping 段 ════"
grep -c "port hopping\|端口跳跃" docs/protocols.md && echo "  ✓ docs covered"

echo
echo "════ ALL SMOKE TESTS PASSED ════"
