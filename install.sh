#!/usr/bin/env bash
# cf-node-trio · 一键 / 菜单式部署
# https://github.com/birdfly/cf-node-trio

set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"
# shellcheck source=lib/singbox.sh
. "$HERE/lib/singbox.sh"
. "$HERE/lib/manage.sh"
for f in "$HERE"/lib/proto-*.sh "$HERE"/lib/ingress-*.sh; do . "$f"; done

usage() {
cat <<EOF
${C_GRN}cf-node-trio${C_RST} · 模块化 VLESS / Hysteria2 / AnyTLS 节点 + 三种 CF 接入

用法:
  bash install.sh                          # 交互菜单
  bash install.sh --proto reality          # 单独装某协议
  bash install.sh --proto ws --ingress cf-cdn --domain n.example.com
  bash install.sh --proto hy2              # 含端口跳跃: 加 HY2_PORT_RANGE=20000:40000
  bash install.sh status                   # 一览当前部署
  bash install.sh subscribe [plain|base64] # 输出全部分享链接
  bash install.sh qr <target>              # 显示 QR (target: reality|hy2|anytls|cf-cdn|argo|tunnel|all)
  bash install.sh port <proto> <newport>   # 修改协议端口 (proto: reality|ws|hy2|anytls)
  bash install.sh bench                    # 跑 bench/speedtest.sh
  bash install.sh uninstall                # 卸载

协议 (--proto):  reality | ws | hy2 | anytls | all
接入 (--ingress): cf-cdn | argo | tunnel

环境变量 (可选):
  REALITY_PORT, REALITY_UUID, REALITY_SNI
  WS_PORT, WS_UUID, WS_PATH
  HY2_PORT, HY2_PASSWORD, HY2_PORT_RANGE (e.g. 20000:40000), HY2_OBFS
  ANYTLS_PORT, ANYTLS_PASSWORD
  CF_CDN_DOMAIN, TUNNEL_DOMAIN, TUNNEL_NAME
EOF
}

interactive() {
  cat <<EOF

${C_BLU}==== 协议 (sing-box 入站) ====${C_RST}
  1) VLESS-Reality   直连, 直接对外, 速度最快, 需暴露端口
  2) VLESS-WS        本地 WS, 配合 CF 走 443, 抗封锁
  3) Hysteria2       QUIC/UDP, 弱网/丢包优势
  4) AnyTLS          多路复用 TLS
  5) 全装 (1+2+3+4)
  0) 跳过协议安装
EOF
  read -rp "选 [1-5/0]: " p
  case $p in
    1) proto_reality_install ;;
    2) proto_ws_install ;;
    3) proto_hy2_install ;;
    4) proto_anytls_install ;;
    5) proto_reality_install; proto_ws_install; proto_hy2_install; proto_anytls_install ;;
    0) info "跳过协议安装" ;;
    *) warn "无效选择" ;;
  esac

  cat <<EOF

${C_BLU}==== CF 接入方式 (基于 VLESS-WS) ====${C_RST}
  1) CF CDN 反代       (要求: 域名 + CF orange-cloud + Caddy)
  2) Argo 临时隧道      (无需账号, 随机子域)
  3) Named Tunnel      (永久子域, 需 cloudflared login)
  0) 跳过接入安装
EOF
  read -rp "选 [1-3/0]: " i
  case $i in
    1) read -rp "请输入 CDN 子域 (如 cdn.example.com): " CF_CDN_DOMAIN
       export CF_CDN_DOMAIN
       ingress_cf_cdn_install ;;
    2) ingress_argo_install ;;
    3) read -rp "请输入 Tunnel 子域 (如 node.example.com): " TUNNEL_DOMAIN
       export TUNNEL_DOMAIN
       ingress_tunnel_install ;;
    0) info "跳过接入安装" ;;
    *) warn "无效选择" ;;
  esac
}

main() {
  # 子命令分发 (不需要 root 的: status / subscribe / qr)
  case ${1:-} in
    status)    detect_os 2>/dev/null; cmd_status; exit 0 ;;
    subscribe) cmd_subscribe "${2:-plain}"; exit 0 ;;
    qr)        cmd_qr "${2:-all}"; exit 0 ;;
    bench)     shift; exec bash "$HERE/bench/speedtest.sh" "$@" ;;
    -h|--help) usage; exit 0 ;;
  esac

  require_root
  detect_os
  ensure_cmd jq
  ensure_cmd curl

  case ${1:-} in
    port)        cmd_port "$2" "$3"; exit 0 ;;
    uninstall)   exec bash "$HERE/uninstall.sh" ;;
  esac

  if [[ $# -eq 0 ]]; then interactive; exit 0; fi

  local proto="" ingress=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --proto)     proto=$2; shift 2 ;;
      --ingress)   ingress=$2; shift 2 ;;
      --domain)    export CF_CDN_DOMAIN=$2; export TUNNEL_DOMAIN=$2; shift 2 ;;
      --bench)     exec bash "$HERE/bench/speedtest.sh" ;;
      --uninstall) exec bash "$HERE/uninstall.sh" ;;
      -h|--help)   usage; exit 0 ;;
      *) die "未知参数: $1" ;;
    esac
  done

  case $proto in
    reality) proto_reality_install ;;
    ws)      proto_ws_install ;;
    hy2)     proto_hy2_install ;;
    anytls)  proto_anytls_install ;;
    all)     proto_reality_install; proto_ws_install; proto_hy2_install; proto_anytls_install ;;
    "")      ;;
    *) die "未知 --proto: $proto" ;;
  esac

  case $ingress in
    cf-cdn) ingress_cf_cdn_install ;;
    argo)   ingress_argo_install ;;
    tunnel) ingress_tunnel_install ;;
    "")     ;;
    *) die "未知 --ingress: $ingress" ;;
  esac

  ok "完成 ✓"
}

main "$@"
