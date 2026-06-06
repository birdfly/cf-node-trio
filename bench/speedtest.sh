#!/usr/bin/env bash
# cf-node-trio · 现场测速
#
# 在 *本机* (作为 VPS owner) 跑, 对 3 种入口分别测:
#   1. ICMP / TLS handshake latency 到 ingress hostname
#   2. 通过该入口拉一个 100 MB 测试文件的下载速率
#
# 不测协议本身 (VLESS-WS payload 一样), 只测 ingress 链路损耗.
#
# 用法:
#   bash bench/speedtest.sh \
#     --cf-cdn    cdn.example.com \
#     --argo      <random>.trycloudflare.com \
#     --tunnel    node.example.com \
#     --direct    1.2.3.4:8443
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
. "$ROOT/lib/common.sh"

# 100 MB 标准测试文件 (Cloudflare 公开镜像)
DL_URL=${DL_URL:-https://speed.cloudflare.com/__down?bytes=104857600}

T_CF_CDN="" T_ARGO="" T_TUNNEL="" T_DIRECT=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --cf-cdn) T_CF_CDN=$2;  shift 2 ;;
    --argo)   T_ARGO=$2;    shift 2 ;;
    --tunnel) T_TUNNEL=$2;  shift 2 ;;
    --direct) T_DIRECT=$2;  shift 2 ;;
    --url)    DL_URL=$2;    shift 2 ;;
    -h|--help) cat <<EOF
bench/speedtest.sh —— cf-node-trio 现场测速

参数:
  --cf-cdn  <hostname>   CF CDN 反代节点入口
  --argo    <hostname>   Argo 临时隧道入口
  --tunnel  <hostname>   Named Tunnel 入口
  --direct  <ip:port>    直连基线 (VLESS-Reality 的 ip:port)
  --url     <url>        替代下载测速 URL (默认 cloudflare 100MB)
EOF
exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
done

[[ -n $T_CF_CDN$T_ARGO$T_TUNNEL$T_DIRECT ]] || die "至少给一个 --cf-cdn / --argo / --tunnel / --direct"

run_test() {
  local label=$1 host=$2

  # 1. ping (3 packets), 拿 平均 RTT
  local rtt="-"
  if [[ $host != *:* ]]; then
    rtt=$(ping -c 3 -W 2 "$host" 2>/dev/null | tail -1 | awk -F'/' '{printf "%.0f", $5}')
    rtt=${rtt:-"-"}
  fi

  # 2. TLS handshake time (curl)
  local tls="-"
  if [[ $host != *:* ]]; then
    tls=$(curl -fsS -o /dev/null --max-time 10 \
                -w '%{time_appconnect}' "https://$host/" 2>/dev/null || echo "-")
    [[ $tls != "-" ]] && tls=$(awk -v t="$tls" 'BEGIN{printf "%.0f", t*1000}')
  fi

  # 3. 下载 100MB, 用 -o /dev/null + -w 拿 throughput
  local dl_url=$DL_URL
  [[ $label == "direct" ]] && dl_url="http://$host/__down?bytes=104857600"

  local speed="-"
  speed=$(curl -fsS -o /dev/null --max-time 90 \
              -w '%{speed_download}' "$dl_url" 2>/dev/null || echo "0")
  speed=$(awk -v s="$speed" 'BEGIN{printf "%.1f", s/1024/1024}')   # MB/s

  printf '| %-10s | %-30s | %5s ms | %5s ms | %6s MB/s |\n' \
         "$label" "$host" "$rtt" "$tls" "$speed"
}

cat <<EOF
| label      | host                           | ping     | TLS handshake | download |
|------------|--------------------------------|----------|---------------|----------|
EOF
[[ -n $T_CF_CDN ]] && run_test "cf-cdn" "$T_CF_CDN"
[[ -n $T_ARGO   ]] && run_test "argo"   "$T_ARGO"
[[ -n $T_TUNNEL ]] && run_test "tunnel" "$T_TUNNEL"
[[ -n $T_DIRECT ]] && run_test "direct" "$T_DIRECT"
