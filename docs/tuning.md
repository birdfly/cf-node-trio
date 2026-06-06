# 内核 / 网络调优

`bash install.sh tune` 会写两个文件:

- `/etc/sysctl.d/99-cf-node-trio.conf` — sysctl 参数
- `/etc/security/limits.d/99-cf-node-trio.conf` — 文件句柄上限

撤销: `bash install.sh untune` (内核值需重启才回到默认, 或者手动 sysctl 改).

## 每条做什么

### BBR + fq (必须搭配)

```
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

BBR 是 Google 2016 提的拥塞控制算法, 对跨洋长肥管道 (high BDP) 比 cubic 强很多.
但 BBR 必须搭配 `fq` qdisc, 单独开 BBR 在某些内核版本无效甚至变差.

### 连接 backlog

```
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_local_port_range = 1024 65535
```

高并发短连接场景下默认 backlog 太小 (Ubuntu 默认 4096), 容易丢 SYN.
端口范围放开到 1024 才能跑多代理后端.

### TCP 缓冲 → 64 MB

```
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
```

BDP = 带宽 × RTT. 跨洋 RTT 150ms × 100Mbps = ~1.9 MB,
单连接想吃满带宽就要让 TCP 缓冲 ≥ BDP. 默认 4MB 在长肥管道下吃不满.
设 64MB 给大文件 / 流式视频留余量.

### UDP 缓冲 (Hysteria2 关键)

```
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
```

Hysteria2 走 QUIC over UDP, 默认 UDP 缓冲对单流大文件不够,
高速场景下日志会刷 `UDP receive buffer too small`. 把 min 抬高可以让 Hy2 跑满带宽.

### TCP 行为

```
net.ipv4.tcp_notsent_lowat = 16384      # 减少 bufferbloat
net.ipv4.tcp_mtu_probing = 1            # 自适应 MTU, 避免黑洞
net.ipv4.tcp_slow_start_after_idle = 0  # 长连接保持窗口, 重连不慢启动
net.ipv4.tcp_tw_reuse = 1               # TIME_WAIT 复用
net.ipv4.tcp_fin_timeout = 15           # 缩短 FIN 等待
net.ipv4.tcp_fastopen = 3               # TFO 客户端 + 服务端都开
```

### 文件句柄

```
* soft nofile 1048576
* hard nofile 1048576
```

默认 1024, sing-box 跑多协议高并发会撞顶. 1M 足够任何场景.

## 看现在生效什么

```bash
bash install.sh status
```

会输出 TCP CC / qdisc / rmem / wmem / somaxconn 当前值, 以及是否应用了本脚本的 tune 文件.

## 注意

- 国内大部分 VPS 厂商 Ubuntu 22+/24+ 自带 BBR 模块, 不用单独装
- 内核 < 4.9 不支持 BBR, 这个脚本不会强升级内核 — 自己 `apt install linux-generic-hwe-*`
- 容器 (docker / lxc 受限的) 大多不能写 sysctl, 脚本会 graceful 跳过
- 改 limits.d 后需要新建 SSH session 才能看到新的 `ulimit -n` (老 session 不刷新)
