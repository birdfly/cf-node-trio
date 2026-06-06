# 现场测速结果 · Live benchmark

> 一次真实测量；非压力测试，仅用来直观比较 3 种入口的 RTT/TLS 链路特性。

## 测试环境

| 项 | 值 |
|---|---|
| 客户端 | macOS, 家庭宽带, 中国大陆 |
| VPS 落地 | 华纳云东京机房, 2 vCPU / 4 GB |
| 协议 | 全部走同一个 sing-box VLESS-WS 入站 (port 10080) |
| 工具 | `ping -c 3` (中位), `curl -w time_appconnect` |
| 时间 | 见 commit log |

## 结果

| 入口模式 | ping (中位) | TLS appconnect | 说明 |
|---|---:|---:|---|
| **CF CDN 反代** | 0.9 ms | 61 ms | 接入 CF Edge anycast, 国内基本无回程 |
| **Argo 临时隧道** | 1.0 ms | 55 ms | 同上, Edge → VPS 的隧道由 CF 选优 |
| **Named Tunnel** | 1.0 ms | 88 ms | 配置相对固定, 偶尔绕路 |
| 直连 VPS:8443 (Reality 基线) | 50.8 ms | — | 直奔东京, 暴露 IP, 但延迟最低 / 损耗最少 |

## 怎么读这张表

- **ping 都是 ~1 ms**：3 种 CF 模式下 ICMP 都打在 CF Edge 节点（anycast），所以"离客户端很近"。这不代表数据真的离你 1ms。
- **TLS appconnect 才反映链路真实耗时**：握手要走 Edge → VPS → Edge 一个回合。
  - CDN 反代 61ms ≈ argo 55ms：两者实际链路差不多
  - Named Tunnel 88ms 略高：可能因为 tunnel 的 origin pull 路径有时不是最优
- **直连 50ms**：单 TCP 握手就到 VPS，无 CDN 中间层。代价是出口 IP 暴露在 client → server 链路中。

## 下载速度为什么不直接放

`curl --proxy` 没法穿透 VLESS-WS，所以无法在服务端单边测出客户端→出口→外网的真实吞吐。
要测：本地客户端连上节点后跑 `speedtest.cloudflare.com`、`fast.com` 或 `curl https://speed.cloudflare.com/__down?bytes=104857600`，3 个节点各跑 3 次取中位。

经验上：

| 入口 | 上限 (典型家庭宽带) |
|---|---|
| 直连 (Reality / Hysteria2) | 接近本地带宽上限, 受 VPS 出口限速影响 |
| CF CDN 反代 | 受 CF Edge ↔ origin 带宽影响, 通常 30–80 Mbps |
| Argo / Named Tunnel | 同 CDN, 单连接吞吐稍低 (HTTP/2 mux 限制) |

## 复现

```bash
bash bench/speedtest.sh \
  --cf-cdn cdn.example.com \
  --argo   xxx.trycloudflare.com \
  --tunnel node.example.com \
  --direct 1.2.3.4:8443
```
