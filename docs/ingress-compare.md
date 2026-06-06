# 三种 CF 接入方式对比

| 维度 | CF CDN 反代 | Argo 临时隧道 | Named Tunnel |
|---|---|---|---|
| **需不需要域名** | 要 (你自己的 + CF 接管 DNS) | **不要** | 要 (CF 账号 + DNS) |
| **需不需要 CF 账号** | 要 (DNS 在 CF) | **不要** | 要 |
| **VPS 端口暴露** | 要开 443 (Caddy 监听) | **不要** | **不要** |
| **VPS IP 暴露** | 不暴露 (CF 橙云) | 不暴露 | 不暴露 |
| **TLS 证书** | Caddy 自动 (Let's Encrypt) | CF 自动 | CF 自动 |
| **子域稳定性** | ✅ 固定 | ❌ 每次重启变 | ✅ 固定 |
| **部署复杂度** | 中 (装 Caddy + 改 DNS) | **最低** (一行 cloudflared) | 高 (需 `cloudflared login` 拿凭证) |
| **断线恢复** | Caddy systemd 自动 | cloudflared systemd 自动, 但子域会变 | cloudflared systemd 自动 |
| **CF 商业风险** | 一般 (CDN 反代非 HTML 资源属灰区) | 高 (条款明禁非 web 用途) | 中 |
| **首次握手延迟** | 中 (TLS 卸载在 Caddy) | 中-低 (CF 优化路径) | 中-高 (有时绕路) |
| **单连接吞吐** | 中-高 | 中 | 中 |
| **适合场景** | 长期主线, 有域名 | 临时分享/测试, 一次性用 | 固定子域 + 想隐藏 VPS, 长期 |

## 选哪个

- **入门 / 临时**: Argo. 一条命令出节点, 不要域名不要账号.
- **长期主用**: CF CDN 反代 或 Named Tunnel.
  - 想完全不在 VPS 上开任何对外端口 → Named Tunnel
  - 想把 Caddy 当 web server 兼用 → CDN 反代
- **三个都要**: 本仓库设计上完全 OK, 同一个 VLESS-WS 后端可以同时挂 3 个入口, 客户端切换即可.

## 一个不显眼但关键的点

CF 三种方式实际上 **共享同一段链路** (Edge → 你的 VPS), 所以理论吞吐天花板差不多.
真正的差别在:
- 部署/维护成本
- 子域是否稳定
- 是否走 cloudflared 隧道 (隧道 vs HTTP 反代的协议开销)

经验上 **Argo 和 Named Tunnel 在长跑稳定性上 < CDN 反代**, 因为 cloudflared 偶尔会重连. 但 CDN 反代要求你保住 Caddy + DNS 配置, 出错代价也高.
