#!/usr/bin/env bash
# 容器内测试 v3 — 含 tune
set -e
cd /work
apt-get update -qq
apt-get install -y -qq jq curl iputils-ping iptables ca-certificates xxd >/dev/null

echo
echo "=== help 含 tune / untune ==="
bash install.sh --help 2>&1 | grep -E "tune|untune"

echo
echo "=== 所有 lib/*.sh 可独立 source ==="
for f in lib/*.sh; do
  bash -c ". $f && echo \"  ok $f\""
done

echo
echo "=== status (空状态, 含 内核/网络 section) ==="
bash install.sh status 2>&1 | head -25

echo
echo "=== tune (容器内 sysctl 写不动, 应该 graceful 跳过) ==="
bash install.sh tune 2>&1 | head -10 || true

echo
echo "=== untune ==="
bash install.sh untune 2>&1 | head -5 || true

echo
echo "=== docs/tuning.md 存在且非空 ==="
wc -l docs/tuning.md

echo
echo "=== ALL OK ==="
