#!/usr/bin/env python3
"""Render the benchmark table into a clean PNG for the README."""
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np
from pathlib import Path

# (label, ping_ms, tls_ms, color, kind)
DATA = [
    ("CF CDN reverse proxy", 0.9, 61, "#f48120", "cf"),   # Cloudflare orange
    ("Argo Quick Tunnel",    1.0, 55, "#fbb040", "cf"),
    ("Named Tunnel",         1.0, 88, "#e87722", "cf"),
    ("Direct (Reality)",    50.8,  0, "#666666", "direct"),
]

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13, 4.5), gridspec_kw={"width_ratios": [1, 1]})
fig.suptitle("cf-node-trio · Ingress latency comparison  (Mac CN → VPS JP)",
             fontsize=14, fontweight="bold")

labels = [d[0] for d in DATA]
y = np.arange(len(labels))
ping  = [d[1] for d in DATA]
tls   = [d[2] for d in DATA]
colors = [d[3] for d in DATA]

# ─── Left: ping ─────────────────────────────────────────────────────────
bars1 = ax1.barh(y, ping, color=colors, edgecolor="white", height=0.6)
ax1.set_yticks(y); ax1.set_yticklabels(labels, fontsize=11)
ax1.invert_yaxis()
ax1.set_xlabel("ping median (ms) — lower is better")
ax1.set_title("ICMP ping  (CF Edge anycast, NOT origin)")
ax1.grid(axis="x", linestyle=":", alpha=0.4)
for b, v in zip(bars1, ping):
    ax1.text(v + max(ping) * 0.015, b.get_y() + b.get_height()/2,
             f"{v:.1f} ms", va="center", fontsize=10)

# ─── Right: TLS handshake ───────────────────────────────────────────────
tls_show = [v if v > 0 else np.nan for v in tls]
bars2 = ax2.barh(y, tls_show, color=colors, edgecolor="white", height=0.6)
ax2.set_yticks(y); ax2.set_yticklabels(labels, fontsize=11)
ax2.invert_yaxis()
ax2.set_xlabel("TLS appconnect (ms) — reflects Edge→origin link")
ax2.set_title("Full TLS handshake  (curl time_appconnect)")
ax2.grid(axis="x", linestyle=":", alpha=0.4)
for b, v in zip(bars2, tls):
    if v > 0:
        ax2.text(v + 2, b.get_y() + b.get_height()/2,
                 f"{v} ms", va="center", fontsize=10)
    else:
        ax2.text(2, b.get_y() + b.get_height()/2, "— (no TLS)",
                 va="center", fontsize=10, style="italic", color="#888")

cf_patch  = mpatches.Patch(color="#f48120", label="CF ingress (CDN / Argo / Tunnel)")
dir_patch = mpatches.Patch(color="#666666", label="Direct (bypass CF)")
fig.legend(handles=[cf_patch, dir_patch], loc="lower center", ncol=2,
           bbox_to_anchor=(0.5, -0.02), fontsize=10)

plt.tight_layout(rect=[0, 0.03, 1, 0.95])

out = Path(__file__).parent / "benchmark.png"
plt.savefig(out, dpi=140, bbox_inches="tight", facecolor="white")
print(f"saved: {out}")
