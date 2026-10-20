# Higher Ed AI Lab — IT Admin Semester Playbook

> **Who this is for:** campus IT admins rolling out an AI lab across a set
> of Dell workstations and running it through a full semester.
>
> **Lab admin quick-start (pilot):** [Developer Deploy Guide](deploy-guide-dev.md).

This guide covers the full lifecycle: initial rollout, per-semester
operation, and end-of-term reset.

## Discovery — sizing the lab

Before ordering hardware, capture:

1. **Peak seat count** — how many students concurrently use the lab at
   peak.
2. **Course mix** — mix of intro (notebook), advanced (per-seat), and
   research (shared compute) courses.
3. **Facility** — power, cooling, networking (10 GbE recommended for
   shared pools).
4. **Identity infrastructure** — Active Directory, Entra ID, or LDAP.
5. **Remote access** — is off-campus student access required?

Tier recommendations by profile:

| Institutional profile | Recommended tier |
|-----------------------|------------------|
| Introductory AI, cross-departmental, budget-constrained | **S** — Shared GB10 pool |
| Dedicated AI teaching lab, advanced coursework | **M** — 1:1 GB10 seats |
| Graduate research + fine-tuning + multi-modal | **L** — 1:1 GB10 + shared frontier pool |

## Design — bill of materials

Sample BOM per tier for a 30-seat lab:

### S — Shared pool

| Component | Count | Notes |
|-----------|------:|-------|
| Dell Pro Precision with GB10 | 10–15 | Shared serving pool, 2–3 students each |
| Student endpoints (existing PCs / laptops) | 30 | Thin clients over the lab LAN |
| Management node | 1 | [Landscape](https://ubuntu.com/landscape)  / [LiteLLM](https://www.litellm.ai/) / JupyterHub host |
| NAS | 1 | Shared model / dataset / home dir storage |
| 10 GbE switch | 1 | Backbone between GB10 pool and NAS |

### M — Allocated 1:1

| Component | Count | Notes |
|-----------|------:|-------|
| Dell Pro Precision with GB10 | 30 | 1:1 — the workstation is the endpoint |
| Dell Pro Precision 9 T4 (RTX PRO 6000) | 0–1 | Optional cohort-shared amplifier, multi-instance or TP |
| Management node | 1 | |
| NAS | 1 | |
| 10 GbE switch | 1 | |

### L — Allocated + shared compute

| Component | Count | Notes |
|-----------|------:|-------|
| Dell Pro Precision with GB10 | 30 | 1:1 seats |
| Dell Pro Precision with GB300 (252 GB HBM3e, aarch64) | 3 | Shared frontier-model pool (~1:10) |
| **or** multi-GPU RTX PRO 6000 tower (Dell Pro Precision 9 T4/T6 class) | 3 | Alternate shared-pool option — one [vLLM](https://github.com/vllm-project/vllm) instance per GPU behind LiteLLM |
| Management node | 1 | |
| NAS | 1 | |
| 10 GbE switch | 1 | |

## Provisioning

Reference automation lane is **Canonical Landscape**:

- **Landscape** for imaging, patching, and course-profile deployment.
- **Ansible** (infrastructure-as-code) can render per-tier
  [Docker](https://www.docker.com/) Compose files and per-course profiles onto nodes. Fleet rollouts
  run without SSH; host administration is per campus policy.

Deployment order for the initial rollout:

1. **NAS + model proxy** — stage model weights and course datasets on the
   NAS. All nodes pull from the local model proxy rather than [Hugging Face](https://huggingface.co/)
   directly.
2. **Golden image** — build one Ubuntu 24.04 image (GB10 and GB300 ship
   DGX OS) with Docker CE + NVIDIA Container Toolkit + management agents.
   Image every node from it.
3. **Course profiles** — one Docker Compose per course, referencing the
   NAS-hosted model paths. Push to nodes via Landscape.
4. **Applications** — JupyterHub (S / L management node), OpenWebUI
   (endpoint), Unsloth Studio / ComfyUI / [OpenCode](https://opencode.ai/) (M / L per-seat).
5. **Identity** — wire JupyterHub / OpenWebUI to campus SSO / IdP.

## Course profiles

A course profile is a Docker Compose file that stands up the
course-specific application stack and points at the course-specific model.

Example course profile (`courses/intro-ai/docker-compose.yml`) — illustrative; for real serving use the recipes, which carry the required Marlin/parser/memory flags and GPU pinning that this snippet omits:

```yaml
services:
  vllm:
    image: vllm/vllm-openai@sha256:cb9bc64f0f038c2c2ebf13b31248fb87aca40c356c3d20f363be087cfcff1fcd
    # the vllm-openai image entrypoint is already `vllm serve`; pass only the model + flags:
    command: ["nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4", "--port", "8000"]
    ports: ["8000:8000"]
    volumes:
      - /mnt/nas/models:/root/.cache/huggingface
  openwebui:
    image: ghcr.io/open-webui/open-webui@sha256:4860ba005ae8f19f08d1e12b0868855b7b339ea0dad9927f196820fc0de04575
    environment:
      - OPENAI_API_BASE_URL=http://vllm:8000/v1
    ports: ["3100:8080"]   # not 3000: that is Grafana
_Commands in this guide run from the repository root (`git clone` this repo and `cd` into it)._

```

Per-platform serving is the same one-command recipes used across the repo —
`recipes/gb10/vllm/docker-nemotron-3.5-lightning-nvfp4.sh`,
`recipes/gb10/vllm/docker-qwen3.8-27b-nvfp4.sh` (coding courses),
`recipes/gb300/vllm/docker-glm-5.3-flash-nvfp4.sh` (frontier tier), and
siblings; catalog at [`docs/recipes/`](../../docs/recipes/).

Faculty select a course profile at the start of class; Landscape
pushes the compose file to the appropriate nodes and starts services.

## N×M scheduling and state reset

One managed fleet serves many courses over a term. Between classes, reset
options:

| Reset method | Time | Use case | Command shape |
|--------------|------|----------|---------------|
| Container reset | ~2 s | Course profile change, model swap | `docker compose down && docker compose up -d` |
| LVM snapshot restore | ~30 s | Per-student home dir wipe | `lvconvert --merge students@baseline` |
| Autoinstall re-image | 3–5 min | End-of-term / curriculum change | Ubuntu autoinstall from PXE / USB |

Reset is a Landscape-orchestrated fleet operation; individual
faculty don't touch nodes directly.

## Identity integration

Wire the following to campus SSO / IdP:

- **JupyterHub** — OAuth2 / LDAP authenticator with per-course group
  scoping.
- **OpenWebUI** — OAuth2 provider config.
- **VDI broker** (if used) — campus SSO.
- **Reverse proxy for remote access** — SSO termination at the proxy;
  students never reach a raw serving port. Terminal-access courses go through
  a jump host, not direct exposure.

## Network and endpoint security

A teaching lab is a shared system with untrusted users, GPUs that are expensive to lose, and a reset cycle that wipes
local evidence. The design goals: students reach the models and their own work and nothing else; every action is
attributable to a person and a course; and the audit trail survives a reset because it never lives only on the machine.
Product names below are examples; confirm exact settings against your vendor's documentation.

### Network segmentation (dedicated, isolated VLANs)

| Segment (example VLAN) | Members | Reachable from students? |
|------------------------|---------|--------------------------|
| **Student seats** (VLAN 110) | seat workstations, thin clients, lab Wi-Fi | n/a — this is where students are |
| **Lab serving** (VLAN 120) | GB10 / GB300 / tower serving nodes, LiteLLM, model proxy | only the gateway/proxy ports below |
| **Lab services** (VLAN 130) | JupyterHub, OpenWebUI, reverse proxy, SSO connector | HTTPS only, via the proxy |
| **Management** (VLAN 190) | Landscape, Prometheus/Grafana, jump host, EDR console, SIEM collector | **never** |
| **Storage** (VLAN 140) | NAS/NFS, model cache | **never** (NFS from serving and services only) |
| **Remote access** (DMZ) | reverse proxy / VDI broker for off-campus | HTTPS + SSO + MFA only |

Rules that matter more than the numbering:
* **Isolate the seat VLAN east-west** (private VLAN / port isolation / `client isolation` on Wi-Fi): a student machine must not
  reach another student machine.
* **Serving nodes live on their own VLAN** so a compromised seat cannot scan them. Recipes publish on all interfaces by default;
  bind them to the serving VLAN address (`--bind <ip>`) and require a key (`DESKSIDE_API_KEY`, or LiteLLM virtual keys).
* **Management is out-of-band to students**: Prometheus, Grafana, Landscape and the EDR console are reachable only from the
  management VLAN and the jump host.
* Use **802.1X / NAC** so seat devices land in the seat VLAN automatically and unknown devices land in a quarantine VLAN.
  Assign the VLAN per device group, not per person.
* **Never expose** a raw vLLM port (`:8000…`), Prometheus (`:9090`), Grafana (`:3000`), or the Docker socket to the seat VLAN or
  the internet. Terminate TLS and SSO at the reverse proxy.

### Allow / deny lists

Flows to permit (everything else default-deny between segments):

| From → to | Ports | Purpose |
|-----------|-------|---------|
| Seat → reverse proxy | 443 | Jupyter, OpenWebUI, API gateway (OpenAI-compatible endpoint) |
| Reverse proxy → LiteLLM / serving nodes | 8000–8099 (only the ports in use) | model traffic, authenticated by key |
| Services → serving nodes | same | JupyterHub / OpenWebUI backends |
| Serving + services → NAS | 2049 (NFS), 111 if your NFS version needs it | models, datasets, homes |
| Management → all nodes | 22 (jump host only), 9100/8000 metrics scrape, EDR/Landscape agent ports | operations and monitoring |
| All nodes → DNS / NTP / SIEM collector | 53, 123, 514/6514 or your collector | resolution, time (needed for audit), log shipping |

Egress (allow-list, not deny-list, for serving nodes and seats):
* **Serving nodes:** package/OS mirror, container registry or pull-through cache, Hugging Face **only through the model proxy**,
  Landscape, EDR cloud. No direct internet otherwise.
* **Seats:** the reverse proxy, campus SSO, the course LMS and documentation your faculty approve. Decide explicitly whether
  public LLM APIs (for example `api.openai.com`, `api.anthropic.com`, `generativelanguage.googleapis.com`) are allowed per course;
  for a "local models only" course, block them at DNS and the firewall.

Deny / block categories on the seat VLAN: anonymizers and VPN/proxy services, Tor, peer-to-peer, remote-admin tools,
public code-execution sandboxes you do not control, and direct access to the storage and management VLANs.

### Tagging

Tags make policy and audit queries cheap. Apply the same vocabulary everywhere:

| Where | Tags / labels |
|-------|---------------|
| Network (NAC, switch/Wi-Fi groups) | `lab-seat`, `lab-serving`, `lab-services`, `lab-mgmt` |
| EDR / device groups | the same four, plus `course-<id>` and `term-<yyyy-s>` on seats |
| Landscape | tags per group and course so scripts target `course-cs101` or `term-2026-fall` |
| LiteLLM virtual keys | metadata `course`, `term`, `user`, per-key budget and rate limit |
| Containers | `--label course=<id> --label owner=<user>`; Prometheus relabels them onto metrics |

### Identity, accounts and containers

* One identity per student from campus SSO; **no shared local accounts**; no `sudo` on seats or serving nodes for students.
* **Docker group membership is root-equivalent**: do not add students to it. Let JupyterHub/the course profile start student
  containers on their behalf, behind a socket proxy or rootless Docker/Podman, and forbid `--privileged`, `--network host`,
  host path mounts outside the student's home, and mounting the Docker socket.
* Student containers run as non-root with the default seccomp profile, a CPU/memory/GPU limit, and images only from the
  internal registry or pull-through cache (image allow-list).
* Give every course its own **LiteLLM key set**: per-student keys with request/token budgets and rate limits so one notebook
  loop cannot starve a class, and revocation at term end.

### Endpoint detection and response (EDR) that survives resets

Policies must work with a reset cycle (container reset between classes, snapshot restore of home directories, re-image at term
end) and with persistent student data:

**Agent identity across resets**
* Do not bake the agent's device identity into the golden image. Generalize it (VDI/golden-image mode where your EDR offers one,
  or clear the sensor ID before sealing) so each re-imaged seat registers once with a stable name (`<room>-<asset-tag>`), not as
  a new device every term. Auto-expire stale device objects after a reset window.
* Keep the agent and its policy **out of the student-writable layer** (system-level install, tamper protection on) so a container
  or home-directory reset neither removes nor weakens it.

**Auditing between resets**
* **Ship telemetry off the box continuously**; never rely on local logs that a reset deletes: EDR events, `auditd` records
  (`execve`, privilege changes, file access to the course data area), container runtime events (start/stop/image/privileges), shell
  session records, and SSH/SSO login events, all to the central SIEM with synchronized time.
* **Snapshot before wipe:** the reset runbook takes a read-only snapshot of the student home volume (LVM/ZFS/NAS snapshot) and
  retains it for your investigation window (for example 30 days) before the wipe or snapshot-restore. Investigators mount snapshots
  read-only on a management host, never on a seat.
* **Persistence enabled** (students keep work across sessions): keep homes on NFS with quotas and per-student ACLs; make the
  working area scannable and auditable, and keep system paths immutable. Persistence is a data-retention decision, so record
  it in the course's retention schedule.
* Tie identities together: EDR device tag + SSO user + LiteLLM key all carry the same `course`/`user` values, so one query shows
  who ran what, from which seat, against which model.

**Policy settings that work well on GPU nodes and seats**
* Prevention: tamper protection on; block unsigned/unknown executables in system paths; restrict removable media; alert on new
  persistence mechanisms (cron, systemd units, SSH keys) in student areas.
* Performance: model weights are large read-only files. Exclude **only** the read-only model cache (for example
  `/mnt/nas/models`, `~/.cache/huggingface`) from real-time scanning and verify those files by hash instead; **do not** exclude
  student-writable homes, container layers or `/tmp`. Schedule full scans off-hours.
* Memory: on GB10 the CPU and GPU share one 128 GB pool, so the agent's footprint counts against model memory. Check the agent's
  resident size and cap it.
* Serving nodes get a stricter profile than seats (no interactive logins, application allow-listing, outbound allow-list).

### Auditing student model usage

* Log **metadata by default** — who (key/user), course, model, time, token counts, latency, status — from the gateway
  (LiteLLM request logs) and the tokenomics dashboard (which stores no prompts or completions).
* Capture **prompts and completions only when policy requires it**, with notice to students, a defined retention period, and
  restricted access by a separate role (academic-integrity office, not lab staff).
* Retain logs in the SIEM, not on the serving node; alert on key sharing (one key, many seats), unusual token volume, and
  blocked-egress attempts.

### Academic-lab considerations
* Publish an acceptable-use policy and monitoring notice at login; align retention with FERPA and institutional policy
  (this guide is not legal advice).
* **Remote cohorts** reach the lab only through the reverse proxy or VDI broker with SSO + MFA; terminal courses use a jump host
  with recorded sessions.
* **Guest and workshop users** get a separate, time-boxed VLAN and keys that expire.
* **Research groups** that need broader access get their own segment and policy, not exceptions in the student segment.

### Reset runbook with audit continuity
1. Freeze new logins to the room; let running jobs finish or checkpoint.
2. Flush and verify log shipping (agent heartbeat, SIEM last-event time per seat).
3. Snapshot student homes (read-only) and record the snapshot ID against the course/term tag.
4. Revoke the course's LiteLLM keys and session tokens.
5. Reset: container reset, snapshot restore, or re-image per the table in the N×M section.
6. Re-register the seat under its stable name, confirm EDR policy and tags, re-issue keys for the next course, re-open logins.

## Monitoring

[Prometheus](https://prometheus.io/) + [Grafana](https://grafana.com/) (served on `:3000`) per node + a central aggregator:

- **GPU utilization** — DCGM exporter.
- **vLLM** `/metrics` — request rate, tok/s, TTFT, KV-cache utilization.
- **JupyterHub / OpenWebUI** — per-user session count and duration.
- **Storage** — NAS free space, per-student home directory growth,
  model-cache size.
- **Fleet health** — node uptime, package drift, patch status via
  Landscape.

## Semester operations

| Event | Action |
|-------|--------|
| **Start of term** | Push course profiles for enrolled courses. Verify all nodes are on the target Ubuntu / driver version. Run a faculty dry-run from a test student account. |
| **Between classes** | Container reset per node (Landscape push). |
| **Mid-semester patch window** | Landscape rolling patch across the fleet with a canary node first. |
| **End of term** | LVM snapshot restore to wipe student home dirs; autoinstall re-image if the curriculum changed. |
| **Model or driver update** | Bump the model tag in the course profile OR re-image with the new driver via Landscape. Canary one node before pushing fleet-wide. |

## Storage lifecycle

- **Model weights** — one copy on the NAS; every node's Docker volume
  mounts the NAS path read-only.
- **Datasets** — course-owned directories on the NAS.
- **Student home directories** — per-student LVM volumes, snapshot at
  baseline for end-of-term reset.
- **Retention** — end-of-term wipe by default; per-student opt-in
  archival if the curriculum requires it.

Planning band (30 seats, one term, indicative): ~2–3 TB usable NAS — see
[Solution overview](README.md#cost-tco).

## Bulk distribution over the LAN (multicast)

NAS mounts work for steady state, but a course swap or a term re-image pushes tens of gigabytes to every seat at once, and
unicast makes the server's uplink the bottleneck: 30 seats each pulling 50 GB means 1.5 TB through one 10 GbE port.
[UDPcast](https://www.udpcast.linux.lu/) sends the stream **once** to all receivers, so the transfer takes the time of a single
copy no matter how many seats are listening. Landscape stays in charge of *which* seats and *when*; the image or model proxy
server sends once.

### Rough time savings (30 seats, 10 GbE server, 10 GbE seats)

Assumptions: the server's usable fan-out is ~1.1 GB/s for unicast; multicast streams at ~1.0 GB/s (the single-copy time) plus
~60 s for the receivers to join; seat NVMe writes keep up. Asset sizes are the ones this template uses.

| Asset | Size | Unicast to 30 seats | Multicast to 30 seats |
|-------|-----:|--------------------:|----------------------:|
| Golden OS image (typical) | 40 GB | ~18 min | ~1.7 min |
| vLLM container image (pinned) | 26 GB | ~12 min | ~1.4 min |
| [Nemotron 3.5 Lightning](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4) weights | 21 GB | ~9.5 min | ~1.4 min |
| [Qwen3.8-27B](https://huggingface.co/nvidia/Qwen3.8-27B-NVFP4) weights | 18 GB | ~8 min | ~1.3 min |
| Course dataset (typical) | 10 GB | ~4.5 min | ~1.2 min |
| [Nemotron 3.5 Super VL](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-NVFP4) weights | 62 GB | ~28 min | ~2.0 min |
| [GLM-5.3-Flash](https://huggingface.co/RedHatAI/GLM-5.3-Flash-NVFP4) weights (GB300 pool) | ~194 GB | ~88 min | ~4.2 min |
| **Course swap**: container image + Lightning + dataset | 57 GB | **~26 min** | **~2 min** |
| **Course swap with Super VL** | 98 GB | ~45 min | ~2.6 min |
| **Term re-image**: OS + image + two models | 105 GB | ~48 min | ~2.8 min |

Unicast time grows with the number of seats; multicast time does not, so the gain is roughly the seat count (about 20–25× at 30
seats after overhead). Over a 1 GbE segment the stream takes ~9× longer on both paths, and the ratio is unchanged.

### How it works with Landscape

1. **Build the tools once per architecture** (`scripts/multicast/udpcast-build.sh`; the distro package can abort large transfers).
2. **Dispatch** from the control host, pointing at the server that holds the content:

```bash
scripts/multicast/multicast-distribute.sh --ids "<landscape ids>" --sender-host <image-server> \
    --src /srv/lab/course-cs101 --dest /srv/lab-cache --bin-dir <udpcast-binaries-for-seat-arch>
```

   The receiver payload (script and binaries) travels inside the Landscape script. The sender waits until every seat has joined,
   so Landscape's dispatch lag does not matter, then streams once. Each seat verifies the stream's sha256 and reports it; the
   command compares every seat with the sender and fails if any differ.
3. **Target by tag** (`course-<id>`, `term-<yyyy-s>`) so one dispatch covers a whole room.

### Measured on a lab segment

Sender and two receivers on one wired 1 GbE VLAN, UDPcast 20250223, aarch64 GB10 hosts:

| Payload | Receivers | Time | Per-receiver rate | Result |
|---------|----------:|-----:|------------------:|--------|
| 2 GB single file | 2 | 22.7 s | ~94 MB/s (about 94% of line rate) | sha256 identical on both |
| 1.3 GB tree (mock golden image + mock Hugging Face cache) | 2 | 15 s | ~88 MB/s | sha256 identical on both |

Each receiver ran at the same rate with two receivers as it would alone, which is why the time does not grow with seat count.
The distro `udpcast` package (20120424) aborted these transfers with a buffer-overflow error; use `scripts/multicast/udpcast-build.sh`.

**Wired only.** A DGX Spark attached over Wi-Fi did not join the stream during the validation window, so treat Wi-Fi seats as
unsupported for this path and pull their content over unicast (or cable them for the swap).

### Network requirements

* **Wired seats and server only.** Multicast over Wi-Fi is sent at the access point's lowest rate; keep this path on the lab VLAN.
* On the lab VLAN enable **IGMP snooping with a querier**, or the switch floods the stream to every port.
* Cap the stream below the slowest link with `--max-bitrate` (for example `900m` on 1 GbE seats).
* UDP ports 9000–9001 between server and seats; the default TTL of 1 keeps the stream inside the VLAN.
* Multicast is unauthenticated: run it on the isolated serving or management VLAN and always verify the sha256 against the value
  the sender prints (or one published through Landscape).

## Common issues

| Symptom | Fix |
|---------|-----|
| Contention on S-tier shared endpoint | Add a LiteLLM router + a second GB10 to the pool; route by course. |
| Faculty course profile fails to load a package | Course profiles must be validated on a pilot node before fleet rollout — build a canary-first workflow into your CI. |
| Storage growth outpacing plan | Snapshot rollover for home dirs + weekly reporting on model-cache size; enforce per-course cache limits. |
| Off-campus student access broken | Verify SSO token TTL + reverse proxy → JupyterHub connectivity separately. |
| First-token latency degrades mid-class | Check `vllm:num_requests_waiting` per pool node; rebalance course groups across nodes with LiteLLM. |

## Related

- [Solution overview](README.md) — sizing, cost framing.
- [Developer Deploy Guide](deploy-guide-dev.md) — pilot / lab-admin
  quick-start.
- [Agentic Coding](../agentic-coding/) — CS-course companion
  (its IT-admin guide covers the serving stack per platform).
- [Agentic Video Search & Summarization](../agentic-vss/) — video search & summarization
  teaching module.
- [OpenClaw on NemoClaw](../openclaw-on-nemoclaw/) — agent-runtime teaching module.
- [S/M/L Sizing](../../docs/sizing.md) ·
  [Glossary](../../docs/glossary.md).
