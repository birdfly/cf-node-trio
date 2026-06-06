# cf-node-trio

> One script that sets up **4 proxy protocols** + **3 Cloudflare ingress modes**
> on a single VPS, so you can actually compare them side-by-side.
>
> English · [中文](README.md)

```
        Protocol layer (sing-box)              Ingress layer (CF / direct)
        ────────────────────────               ───────────────────────────
        ❶ VLESS-Reality       ──┐
        ❷ VLESS-WS            ──┤              ❶ CF CDN reverse proxy (Caddy)
        ❸ Hysteria2 (QUIC)    ──┼─ any combo ─→ ❷ CF Argo Quick Tunnel
        ❹ AnyTLS              ──┘              ❸ CF Named Tunnel
                                               ❹ Direct (bypass CF)
```

## What this is

Most "set up a node" tutorials are one-shot: install sing-box, run cloudflared, done.
In reality the choice space is much wider: 4 common protocols × 3 CF ingress modes = 12 combos,
each with different latency, throughput, stealth, and deployment cost.

This repo does three things:

1. **One `install.sh`** that wires up any subset of those 12 combos with no conflicts
2. **A `bench/speedtest.sh`** for on-site latency / throughput measurements
3. **Docs** that actually explain the real differences between the three CF ingress modes — not just rephrased marketing

If you just want a working node, run `install.sh` with defaults.
If you want to understand *why* Argo needs no domain, why CDN reverse proxy needs orange-cloud, and why Named Tunnel needs `cloudflared login`, read `docs/`.

## What it's not

- ❌ **Not a paid-VPN backend** — no user mgmt, no traffic accounting, no panel
- ❌ **Not production-grade** — no monitoring, alerting, backup/restore
- ❌ **Not a way around any law** — comply with your jurisdiction, this is for technical research

## Quick start

VPS: Ubuntu 22+/24+ or Debian 12+ (others likely work), root, public IPv4.

```bash
git clone https://github.com/birdfly/cf-node-trio
cd cf-node-trio
sudo bash install.sh
```

Follow the menu (protocol → ingress). At the end you'll get a `vless://...` link
you can paste into Mihomo / sing-box / NekoBox / v2rayN.

One-liner (Argo, no domain needed):

```bash
sudo bash install.sh --proto ws --ingress argo
```

With a domain on CF CDN:

```bash
sudo bash install.sh \
  --proto ws \
  --ingress cf-cdn \
  --domain cdn.your-domain.com
```

## How the protocols differ

Full details in [`docs/protocols.md`](docs/protocols.md). One-liners:

| Protocol | One-liner |
|---|---|
| VLESS-Reality | Borrows a real site's TLS cert for SNI; handshake looks like a visit to that site. Fastest direct. |
| VLESS-WS      | Plain WS locally, TLS done by the previous hop. **All 3 CF ingresses speak this.** |
| Hysteria2     | QUIC over UDP, BBR-like CC. Wins on lossy / mobile networks. |
| AnyTLS        | sing-box 1.10+ TLS-mux proxy. |

| CF ingress | One-liner |
|---|---|
| **CF CDN reverse proxy** | Domain on orange-cloud, Caddy listens on 443 and reverse-proxies to local. Stable subdomain, most widely used. |
| **Argo Quick Tunnel** | One `cloudflared tunnel --url` line. No domain, no CF account. Random subdomain, changes on restart. |
| **Named Tunnel** | Permanent subdomain, requires a one-time `cloudflared login`. VPS opens no inbound ports. |

## Three CF ingress modes — comparison

| Aspect | CDN reverse proxy | Argo Quick | Named Tunnel |
|---|---|---|---|
| Needs a domain | ✓ | ✗ | ✓ |
| Needs CF account | ✓ | ✗ | ✓ |
| VPS opens 443 | ✓ | ✗ | ✗ |
| Stable subdomain | ✓ | ✗ | ✓ |
| Deployment | medium | **easiest** | high |
| Best for | long-term main | one-off / share | long-term + hide VPS |

Full table (throughput / failover / ToS risk): [`docs/ingress-compare.md`](docs/ingress-compare.md)

## Benchmark

A single live measurement (Mac client / home broadband / mainland CN, VPS in Tokyo JP):

![benchmark](bench/benchmark.png)

| Ingress | ping (median) | TLS appconnect |
|---|---:|---:|
| **CF CDN reverse proxy** | 0.9 ms | 61 ms |
| **Argo Quick Tunnel**    | 1.0 ms | 55 ms |
| **Named Tunnel**         | 1.0 ms | 88 ms |
| Direct VPS:8443 (Reality baseline) | 50.8 ms | — |

**How to read**: 1ms pings just mean ICMP hits CF Edge anycast (close to the user).
The TLS handshake still has to traverse Edge → origin VPS, hence ~55–90 ms.
Direct is 50 ms single-trip to Tokyo, no CDN in the middle, but exposes VPS IP.

Methodology + how to reproduce: [`bench/results.md`](bench/results.md)

```bash
bash bench/speedtest.sh \
  --cf-cdn cdn.example.com \
  --argo   xxx.trycloudflare.com \
  --tunnel node.example.com \
  --direct 1.2.3.4:8443
```

## Client configs

- sing-box: [`examples/sing-box-client.json`](examples/sing-box-client.json)
- Mihomo / Clash Meta: [`examples/clash.yaml`](examples/clash.yaml)

## Uninstall

```bash
sudo bash uninstall.sh
```

Stops the systemd units, strips `# ── cf-node-trio:` blocks from Caddyfile, and *moves* config dirs to `/root/cf-node-trio-uninstall-<timestamp>/` instead of deleting — so you can roll back.

## Why I wrote this

I run two VPSes (Japan + AWS Lightsail US) plus a ChatGPT US API proxy, a Hermes Agent, and a personal site. I've cycled through all 4 protocols × 3 ingress modes more times than I'd like, and every fresh VPS made me redo the dance. This script is what I use myself; open-sourcing in case it helps.

If you also want "set it up once and keep the choice open," this is for you.

## Contributing

PRs welcome. Especially:

- New protocols in `lib/proto-*.sh`
- Other CDN ingresses (CDN77 / Bunny / CloudFront)
- `bench/` data from other regions (please note region/ISP in your commit)

Keep `set -euo pipefail`. Each `lib/*.sh` should be source-able independently.

## Star history

<a href="https://star-history.com/#birdfly/cf-node-trio&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)"
            srcset="https://api.star-history.com/svg?repos=birdfly/cf-node-trio&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)"
            srcset="https://api.star-history.com/svg?repos=birdfly/cf-node-trio&type=Date" />
    <img alt="Star History Chart"
         src="https://api.star-history.com/svg?repos=birdfly/cf-node-trio&type=Date" />
  </picture>
</a>

## License

[MIT](LICENSE) © 2026 birdfly
