# 架构 · Architecture

```
                                              ╔═════════════════════════════╗
                                              ║          VPS (你)           ║
                                              ║                             ║
                                              ║  ┌──────────────────────┐   ║
                ┌─── ❶ CF CDN 反代 ─────────────────→ Caddy :443         │   ║
                │           (橙云 + TLS 卸载)    ║  └──────────┬───────────┘   ║
                │                                ║              │              ║
   client ──→ ──┼─── ❷ Argo 临时隧道 ────────────────→ cloudflared 临时 ───┐   ║
 (任意网络)     │     (trycloudflare.com)         ║                    │   ║
                │                                ║                    ↓   ║
                ├─── ❸ Named Tunnel ────────────────→ cloudflared 永久 ─→ sing-box VLESS-WS :10080
                │           (your-domain.com)     ║                          ↓   ║
                │                                ║                  outbound (direct / 美国中继)
                │
                └─── ❹ Reality / Hy2 / AnyTLS (直连)→ sing-box :8443/:32143/...
                            (绕过 CF, 暴露 VPS IP)
```

## 一句话总结

- 协议 (sing-box 入站) 决定 **传输怎么加密**
- 入口 (CF CDN / Argo / Named Tunnel / 直连) 决定 **怎么找到 VPS**

二者互相独立，可以任意组合。最常见两组：

| 组合 | 场景 |
|---|---|
| VLESS-WS + CF CDN | 抗封锁主线, 域名/IP 都藏在 CF 后面 |
| VLESS-Reality 直连 | 速度/延迟最优, 但要保护 VPS IP |

## 为什么 sing-box

- 一个 binary 同时支持 4 种协议入站
- config 是合法 JSON，jq 可直接合并
- 同一进程内可做 outbound 路由（比如把 ChatGPT 请求转到美国出口）

## 为什么 Caddy 做 CDN 反代

- 自动签发 Let's Encrypt 证书（不需要手动 certbot）
- Caddyfile 一行 `reverse_proxy 127.0.0.1:10080` 就接好
- WS upgrade 头透传零配置
