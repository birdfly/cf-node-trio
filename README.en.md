# cf-node-trio

> Set up 4 proxy protocols + 3 Cloudflare ingress modes on one VPS. Same backend, client picks.
>
> [中文](README.md)

![benchmark](bench/benchmark.png)

Tested from my home network, VPS in Tokyo. How to read this: [bench/results.md](bench/results.md)

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/birdfly/cf-node-trio/main/install.sh)
```

or:

```bash
git clone https://github.com/birdfly/cf-node-trio
cd cf-node-trio
sudo bash install.sh
```

Two menu prompts. It spits out a `vless://...` at the end.

## Protocols

`reality` · `ws` · `hy2` · `anytls`

```bash
sudo bash install.sh --proto reality
sudo bash install.sh --proto hy2                          # plain
sudo HY2_PORT_RANGE=20000:40000 \
     bash install.sh --proto hy2                          # port hopping
sudo HY2_PORT_RANGE=20000:40000 \
     HY2_OBFS=$(openssl rand -hex 8) \
     bash install.sh --proto hy2                          # hop + obfs
sudo bash install.sh --proto all                          # all four
```

## CF ingress (uses ws)

`cf-cdn` · `argo` · `tunnel`

```bash
sudo bash install.sh --proto ws --ingress argo            # no domain, quickest
sudo bash install.sh --proto ws --ingress cf-cdn --domain cdn.example.com
sudo bash install.sh --proto ws --ingress tunnel --domain n.example.com
```

One-liner:

| | needs domain | needs CF account | opens 443 | stable subdomain |
|---|---|---|---|---|
| cf-cdn | ✓ | ✓ | ✓ | ✓ |
| argo   | ✗ | ✗ | ✗ | ✗ |
| tunnel | ✓ | ✓ | ✗ | ✓ |

Full comparison: [docs/ingress-compare.md](docs/ingress-compare.md)

## Use

```bash
sudo bash install.sh status              # what's installed
bash install.sh subscribe                # all share links
bash install.sh subscribe base64         # subscription URL format
bash install.sh qr all                   # all QR codes (ANSI)
sudo bash install.sh port hy2 8443       # change a port
sudo bash install.sh tune                # apply BBR + big buffers + high concurrency
sudo bash install.sh uninstall           # uninstall (moves config to backup)
```

What `tune` does: BBR+fq, 64MB TCP buffers, UDP buffers (matters for Hy2),
backlog 65535, nofile 1M, ... Full breakdown: [docs/tuning.md](docs/tuning.md)

## Reproduce benchmark

```bash
bash bench/speedtest.sh \
  --cf-cdn cdn.example.com \
  --argo   xxx.trycloudflare.com \
  --tunnel n.example.com \
  --direct 1.2.3.4:8443
```

Numbers + how to read: [bench/results.md](bench/results.md)

## Clients

- Mihomo / Clash Meta: [examples/clash.yaml](examples/clash.yaml)
- sing-box: [examples/sing-box-client.json](examples/sing-box-client.json)

## Docs

- [Architecture](docs/architecture.md)
- [4 protocols compared](docs/protocols.md)
- [3 CF ingress modes compared](docs/ingress-compare.md)
- [Kernel / network tuning](docs/tuning.md)

## Star history

<a href="https://star-history.com/#birdfly/cf-node-trio&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=birdfly/cf-node-trio&type=Date&theme=dark" />
    <img alt="Star History" src="https://api.star-history.com/svg?repos=birdfly/cf-node-trio&type=Date" />
  </picture>
</a>

## License

[MIT](LICENSE)
