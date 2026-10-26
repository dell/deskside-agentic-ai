# Deskside tokenomics monitoring

Every serving recipe starts (idempotently) a shared **Prometheus + Grafana** pair
that tracks the *economics* of the platform, not its payload: tokens served,
cloud-API-equivalent spend vs amortised on-prem cost, $ per 1M output tokens,
platform utilisation, per-session tok/s vs the responsiveness floor, prefix-cache
hit rate. No prompts or completions are collected -- only vLLM `/metrics`
counters/gauges.

| Piece | Where |
|-------|-------|
| Wiring (called by every recipe) | `recipes/lib/monitoring.sh` |
| Prometheus config (file-based discovery) | `monitoring/prometheus.yml` |
| Dashboard template (placeholders `__CLOUD_IN__` etc. are rendered at deploy) | `monitoring/tokenomics.dashboard.template.json` |
| Runtime state | `~/.deskside/monitoring/` (targets, rendered config, Grafana admin password `0600`) |

Containers: `deskside-prometheus`, `deskside-grafana` (pinned images, `--network host`,
`--restart unless-stopped`, bound to `127.0.0.1` by default). Ports start at 9090 /
3000 and move up automatically if taken (the chosen URLs are printed by the recipe and
by `recipes/lib/health.sh`).

## Cost assumptions (edit in the dashboard header or set env before running a recipe)

| Env | Default | Meaning |
|-----|---------|---------|
| `DESKSIDE_CLOUD_IN_PER_M` | 3.00 | cloud $/1M input tokens -- becomes the **Custom (from deploy env)** picker option |
| `DESKSIDE_CLOUD_OUT_PER_M` | 15.00 | cloud $/1M output tokens -- **Custom (from deploy env)** option |
| `DESKSIDE_SYSTEM_PRICE` | 20000 | system price USD (planning default: T2-class list ~$20K; set your own quote) |
| `DESKSIDE_AMORT_MONTHS` | 24 | amortisation horizon (planning default: 2 years) |
| `DESKSIDE_WATTS` | 600 | average system draw |
| `DESKSIDE_KWH_PRICE` | 0.15 | $/kWh |

The dashboard's **compare against** picker (top of the page) drives the
cloud-equivalent spend and savings panels at published list prices for
frontier models -- static assumption series in
[`model-prices.yml`](https://github.com/dell/deskside-agentic-ai/blob/main/monitoring/model-prices.yml), captured 2026-10-20. To refresh
prices, edit that file and re-run any recipe (the monitoring stack re-renders
its config at start); to compare against your contracted rate, pick
**Custom (from deploy env)**. The remaining defaults are planning
placeholders; the dashboard labels every cost panel as assumption-driven.

## Other knobs
`DESKSIDE_MONITORING=0` or `--no-monitoring` skips it; `DESKSIDE_MON_BIND` (default
`127.0.0.1`; set `0.0.0.0` to share the dashboard on the LAN -- put an
authenticating proxy in front); `DESKSIDE_PROM_PORT`, `DESKSIDE_GRAFANA_PORT`,
`DESKSIDE_PROM_RETENTION` (30d). Teardown: `recipes/lib/monitoring.sh down`.
