# 四种协议技术原理

## VLESS-Reality (直连)

- 基于 TLS 1.3, 借用一个 **真实公网站点** (默认 `www.cloudflare.com`) 的证书做 SNI 伪装
- 握手阶段对外完全像在访问那个伪装站点 → **抗主动探测**
- 握手成功后由 sing-box 解出 VLESS 流量 (flow=`xtls-rprx-vision` 直传)
- **优点**: 直连最快, 不依赖任何 CDN/隧道, 不需要域名
- **缺点**: VPS IP 暴露在 client → server 链路里

## VLESS-WS (over plaintext, 配合 ingress)

- 本地 sing-box 只监听 `127.0.0.1:10080`, 协议层就是 plain WebSocket 包了一层 VLESS
- 上一跳 (Caddy / cloudflared) 负责 TLS 卸载, 把 WS 帧透传给本地
- **优点**: CF 三种入口都吃这个协议, 一份后端三种暴露
- **缺点**: 单独存在没意义, 必须有 ingress 在前

## Hysteria2

- 基于 QUIC (UDP/443 或自选端口) + 自带 BBR-like 拥塞控制
- 弱网/丢包场景下显著优于 TCP-based 协议
- 自签证书 + `insecure=1` 即可工作
- **优点**: 同等带宽下 throughput 通常更高; 抢占 UDP 优先级
- **缺点**: 部分 ISP/酒店 WiFi 限 UDP, 此时不如 TCP

## AnyTLS

- sing-box 1.10+ 新协议, 把 TLS 当传输层 + 多路复用
- 比 Trojan/VLESS-TLS 多了一层 mux, 减少握手次数
- **优点**: 长连接复用好, 适合"开 N 个 tab 并发"的场景
- **缺点**: 客户端支持面比 VLESS 窄

## 简单选型

| 你的优先级 | 推荐 |
|---|---|
| 最快 / 最低延迟 | VLESS-Reality 直连 |
| 抗封锁 / 隐藏 IP | VLESS-WS + CF (本仓库主题) |
| 弱网 / 移动 4G | Hysteria2 |
| 高并发短连接 | AnyTLS |

`install.sh` 默认 4 个一次装齐 (互不冲突, 各占一个端口), 客户端按需切.
