# cf-node-trio

> 一份脚本同时把 **4 种代理协议** + **3 种 Cloudflare 接入方式** 在一台 VPS 上摆出来,
> 帮你横向看清自建节点的实际选择空间.
>
> 中文版 (默认) · [English](README.en.md)

```
        协议层 (sing-box)                     入口层 (CF / 直连)
        ──────────────────                    ────────────────────
        ❶ VLESS-Reality       ──┐
        ❷ VLESS-WS            ──┤             ❶ CF CDN 反代 (Caddy)
        ❸ Hysteria2 (QUIC)    ──┼─ 任选组合 ─→ ❷ CF Argo 临时隧道
        ❹ AnyTLS              ──┘             ❸ CF Named Tunnel
                                              ❹ 直连 (绕过 CF)
```

## 这是什么

很多教程把 "搭节点" 当成一锤子的事 — 装个 sing-box, 跑个 cloudflared, 完事.
但实际选择面非常宽: 4 个常见协议 × 3 种 CF 接入方式 = 12 种组合, 各自的延迟/吞吐/隐蔽性/部署难度都不同.

这个仓库做三件事:

1. 一个 `install.sh` 把 12 种组合里你想要的那些 **一键摆好**, 互不冲突
2. 一份 `bench/speedtest.sh` 让你 **当场测** 每种入口的实际延迟和吞吐
3. 文档里把 **三种 CF 入口的真实差别** 说清楚, 不是抄官方介绍

如果你只想要一个能用的节点, 跑 `install.sh` 全部默认值即可.
如果你想搞清楚为什么 Argo 不要域名, CDN 反代要橙云, Named Tunnel 要 `cloudflared login`, 看 `docs/`.

## 不是什么

- ❌ **不是机场后端** — 没有用户管理, 没有流量统计, 没有面板
- ❌ **不是生产级** — 没有监控, 没有告警, 没有备份恢复
- ❌ **不是绕过任何法律** — 请遵守你所在地的法律法规, 仅作技术研究

## 快速开始

VPS 要求: Ubuntu 22+/24+ 或 Debian 12+ (其他大概率也行), root, 公网 IP.

```bash
git clone https://github.com/birdfly/cf-node-trio
cd cf-node-trio
sudo bash install.sh
```

跟着菜单走两步, 第一步选协议, 第二步选入口. 完成后会打印一行 `vless://...` 之类的分享链接, 直接贴进 Mihomo / sing-box / NekoBox 客户端导入.

只想一条命令出节点 (Argo 临时, 无需域名):

```bash
sudo bash install.sh --proto ws --ingress argo
```

带域名上 CF CDN:

```bash
sudo bash install.sh \
  --proto ws \
  --ingress cf-cdn \
  --domain cdn.your-domain.com
```

## 技术原理

详细原理见 [`docs/protocols.md`](docs/protocols.md) 和 [`docs/ingress-compare.md`](docs/ingress-compare.md). 这里给一句话版:

| 协议 | 一句话 |
|---|---|
| VLESS-Reality | 借公网站证书的 SNI, 握手时看起来在访问那个站. 直连最快. |
| VLESS-WS      | 本地 plain WS, TLS 由前一跳卸载. **CF 三种入口都吃这个协议**. |
| Hysteria2     | QUIC over UDP, 弱网/移动 4G 强. |
| AnyTLS        | sing-box 1.10+ 的多路复用 TLS 代理. |

| CF 入口 | 一句话 |
|---|---|
| **CF CDN 反代** | 域名挂橙云, Caddy 监听 443 反代到本地. 子域稳定, 用得最广. |
| **Argo 临时隧道** | 一条 `cloudflared tunnel --url` 命令出节点. 不要域名, 不要 CF 账号. 子域随机, 重启会换. |
| **Named Tunnel** | 永久子域, 需 `cloudflared login` 一次拿凭证. VPS 端不用开任何对外端口. |

## 三种 CF 入口对比 (节选)

| 维度 | CF CDN 反代 | Argo 临时 | Named Tunnel |
|---|---|---|---|
| 要域名 | ✓ | ✗ | ✓ |
| 要 CF 账号 | ✓ | ✗ | ✓ |
| VPS 开 443 | ✓ | ✗ | ✗ |
| 子域稳定 | ✓ | ✗ | ✓ |
| 部署难度 | 中 | **最低** | 高 |
| 适合 | 长期主线 | 临时分享 | 长期 + 隐藏 VPS |

完整对比 (含吞吐 / 断线恢复 / 商业风险): [`docs/ingress-compare.md`](docs/ingress-compare.md)

## 测速结果

一次真实测量 (Mac 客户端 / 家庭宽带 / 中国大陆, VPS 在日本东京):

| 入口模式 | ping (中位) | TLS appconnect |
|---|---:|---:|
| **CF CDN 反代** | 0.9 ms | 61 ms |
| **Argo 临时隧道** | 1.0 ms | 55 ms |
| **Named Tunnel** | 1.0 ms | 88 ms |
| 直连 VPS:8443 (Reality) | 50.8 ms | — |

**怎么读**: ping 都 1ms 是因为打的是 CF Edge 的 anycast IP (国内本地有节点),
但实际数据要走 Edge → 日本 VPS, 所以 TLS 握手仍要 ~55-90ms.
直连 50ms 是单程到东京, 没有 CDN 中间层, 但暴露 VPS IP.

完整方法 + 怎么自己跑: [`bench/results.md`](bench/results.md)

```bash
bash bench/speedtest.sh \
  --cf-cdn cdn.example.com \
  --argo   xxx.trycloudflare.com \
  --tunnel node.example.com \
  --direct 1.2.3.4:8443
```

## 客户端示例

- sing-box: [`examples/sing-box-client.json`](examples/sing-box-client.json)
- Mihomo / Clash Meta: [`examples/clash.yaml`](examples/clash.yaml)

## 卸载

```bash
sudo bash uninstall.sh
```

会把所有 systemd 服务停掉, Caddyfile 里的 `# ── cf-node-trio:` 块清理掉, 配置目录移到 `/root/cf-node-trio-uninstall-<timestamp>/` 而不是直接删 — 给你后悔的机会.

## 我为什么写这个

我有两台 VPS (日本华纳云 + AWS Lightsail 美国), 加上 ChatGPT 美区 API 代理 / Hermes Agent / 个人内容站, 一来二去把 4 协议 × 3 入口几乎都跑过. 每次新装一台 VPS 都从零搭一遍很烦, 而且每次都会想 "这次到底走哪个". 这份脚本是我自己写来给自己复用的, 顺便开源.

如果你也是 "懒得记, 但希望保留选择空间" 的人, 这个仓库给你省点事.

## 贡献

PR 欢迎. 主要欢迎:

- 新协议的 `lib/proto-*.sh`
- 其他 CDN 入口 (CDN77 / Bunny / AWS CloudFront)
- 不同地理位置的 `bench/` 实测数据 (附 commit 写 region/ISP)

请保持 `set -euo pipefail`, 每个 lib 文件可以独立 source, 不依赖 `install.sh` 的菜单状态.

## 协议

[MIT](LICENSE) © 2026 birdfly
