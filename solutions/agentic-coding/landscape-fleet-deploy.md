# Fleet deployment via Canonical Landscape (Agentic Coding solution)

> **Who this is for:** IT admins managing a fleet of enrolled Ubuntu
> workstations (DGX Spark / Precision / DGX Station) who want serving-recipe
> rollouts **without SSH** — launched from [Canonical Landscape](https://ubuntu.com/landscape), logged in the
> Landscape activity feed, repeatable from CI.
>
> **Companion docs:** [IT-Admin Guide](it-admin-guide.md) (single-node
> setup), [Solution overview](README.md) (sizing + recipes),
> [`scripts/landscape/`](../../scripts/landscape/) (the tooling).

## How the pieces fit

```
control host                       enrolled device (per fleet member)
─────────────                      ─────────────────────────────────
landscape_client.py  ──HTTPS────►  landscape-client
  runscript (CreateScript            ScriptExecution plugin runs the
  + ExecuteScript, Bearer JWT)        payload as root/user, returns
  pollscript ◄── activity result     stdout as the activity result
```

* **Landscape picks *who*** (the fleet inventory), *the script says **how***
  (it just runs this repo's recipe). One execution authority per box at a
  time — don't layer a second config manager onto the same ports/compose.
* The payloads in [`scripts/landscape/`](../../scripts/landscape/) are plain
  bash; you can run the identical script by hand over SSH during bring-up —
  the converged state is observationally the same.

## Prerequisites

| Check | Command (on the device) | Notes |
|-------|------------------------|-------|
| Enrolled + **Accepted** | `landscape_client.py computers` lists it | Newly registered machines may sit **Pending**; acceptance is UI-only on SaaS. Re-running `landscape-config` on a registered machine **re-registers** it (new id). |
| ScriptExecution on | see §Step 1 | One-time, needs sudo (console or existing root). |
| Disk ≥ ~60 GB free | `df -h /` | image (~35 GB) + weights (~21 GB) + slack. |
| [Docker](https://www.docker.com/) nvidia runtime | `docker info \| grep -iA1 Runtimes` | Stock DGX Spark lacks it — §Step 2 self-heals. |
| Internet to HF + Docker Hub (or pre-seeded cache) | `curl -I https://huggingface.co` | Air-gapped: pre-seed `~/.cache/huggingface` per the IT-Admin guide. |
| GB10 memory headroom | `nvidia-smi` process list | Unified memory: local ollama/benchmark strays shrink the pool; on GB10 `--query-gpu=memory.used` reports *N/A*. |

## Step 1 — Enable remote script execution (once per device)

Run [`scripts/landscape/enable-script-execution.sh`](../../scripts/landscape/enable-script-execution.sh)
on the device with sudo (`<your-account>` = Landscape account name). Allow one
client exchange (~4 min). Two traps, both in the script header:
`--silent` is required without a TTY, and already-registered machines come
back with a **new computer id**, possibly **Pending** approval.

Prove it with a trivial payload before fleet-running anything:

```bash
ID=$(python3 scripts/landscape/landscape_client.py computers | awk '/<device>/{print $1}')
printf '#!/bin/bash\nhostname\nid -un\n' > /tmp/exec-check.sh
python3 scripts/landscape/landscape_client.py runscript --file /tmp/exec-check.sh --ids "$ID" --user root --limit 60
python3 scripts/landscape/landscape_client.py pollscript --group <group-id> --timeout 240
```

`"plugin which should handle it isn't available"` ⇒ ScriptExecution is off
(or the registration is still Pending — on the device,
`/var/log/landscape/broker.log` showing accepted types `test` only = Pending).

## Step 2 — Deploy (per device or by query)

Staging (once per device — file transfer only): sync this repo to
`/opt/deskside-agentic-ai-solutions-for-nvidia` and, if the fleet serves under
a non-root user, ensure the HF cache + `token` live where the payload points
`HF_HOME` (root-context scripts do **not** see `/home/<user>`).

```bash
python3 scripts/landscape/landscape_client.py runscript \
  --file scripts/landscape/deploy-serving-recipe.sh --ids "$ID" --user root --limit 1800
python3 scripts/landscape/landscape_client.py pollscript --group <group-id> --timeout 2400
```

The payload: self-heals the docker nvidia runtime → pre-pulls the image (the
recipes cap their own pull at 60 s) → runs the recipe → **hard gate**: exits 1
unless the container is up. Configure per fleet by editing the env block at
the top (`RECIPE`, `IMAGE`, `CONTAINER`, `HF_HOME`) — e.g. Precision tiers:
`RECIPE=$REPO_DIR/recipes/precision/vllm/docker-nemotron-3.5-lightning-nvfp4.sh
CONTAINER=lightning-3.5-precision-8000` (Precision names carry the port; ports count up from 8000). The payload now fails (exit 1) unless the recipe's own readiness contract passes, and the container gate matches the exact name.

## Step 3 — Verify (one exchange cycle)

```bash
python3 scripts/landscape/landscape_client.py runscript \
  --file scripts/landscape/verify-serving.sh --ids "$ID" --user root --limit 3000
```

It loops internally (`VERIFY_ITERS` × 30 s, default ~40 min: first boot
downloads ~21 GB of weights — raise it on slow links),
then checks `/health`, lists served model aliases, and runs one smoke chat
completion (`max_tokens 512` — reasoning models spend small budgets entirely
on thinking). Prints `READY` + `smoke: FLEET DEPLOY OK` on success,
`DIED` + logs on failure.

## Step 4 — Close root script execution (deploy-time only)

Root is needed only while the rollout runs. Once Step 3 reports healthy, remove the plugin and the script users so the
device keeps reporting and patching but can no longer be told to run scripts:

```bash
python3 scripts/landscape/landscape_client.py runscript \
  --file scripts/landscape/disable-script-execution.sh --ids "$ID" --user root --limit 120
```

The script edits `/etc/landscape/client.conf` in place (backup kept), drops `ScriptExecution` from
`include_manager_plugins`, clears `script_users`, and restarts `landscape-client`; it does not re-register the machine. This is the
last script the fleet runs. For the next rollout window re-run Step 1 (`enable-script-execution.sh`), deploy, verify, then close it
again. If a script must stay possible between rollouts, set `script_users` to a dedicated non-root account instead of root.

## Operating expectations & gotchas

1. **Result lag is normal.** Busy/slow clients report script results 15–30
   min after execution; `delivered` ≠ done — only `succeeded`/`failed` resolve
   an activity. Poll patiently; the self-loop payloads exist precisely because
   each round-trip is expensive.

2. **Unified memory (GB10):** if `--gpu-memory-utilization 0.7` fails with
   *"Free memory … less than desired"*, free the squatters or lower the
   utilization env var the recipe exposes.

3. **Slow links:** cold-cache pulls can overrun the script `--limit` before
    anything reports. Stage the image (`docker pull`) and weights
    (`docker run --rm --entrypoint hf <image> download <model-id>`) over
    ssh first — staging only, the daemon dedupes concurrent pulls. And if a
    group stays `delivered` forever, treat ssh-visible device state as ground
    truth: short completed scripts report reliably, killed long ones often
    don't.

## Teardown / rollback

- Rollback = rerun Step 2 with the previous image tag (`IMAGE=<old-tag>` —
  the recipe removes the old container automatically).
- Teardown = `docker rm -f <container>` + optional `sudo rm -rf` of the
  model cache (see IT-Admin guide §9) — dispatchable as a one-line script.


