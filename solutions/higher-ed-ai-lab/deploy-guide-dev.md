# Higher Ed AI Lab — Lab Admin Quick-Start

> **Who this is for:** lab admins / faculty standing up a pilot AI lab on a
> handful of Dell Pro Precision with GB10 systems for evaluation before
> committing to a full deployment.
>
> **IT admin path:** [IT-Admin Guide](it-admin-guide.md).

## Prerequisites

- 1–3 Dell Pro Precision with GB10 systems for a pilot (plus one Dell Pro
  Dell Pro Precision 9 T4 (RTX PRO 6000) or Dell Pro Precision with GB300 if exploring the
  shared-compute options).
- Ubuntu 24.04 LTS or newer on each system (GB10 ships with DGX OS).
- A shared NAS / NFS mount reachable by every system (even a small NAS is
  fine for a pilot).
- A single [Hugging Face](https://huggingface.co/) token for the group.
- One test student account per pilot use case.

## 1) Bring up a shared LLM endpoint on one GB10

_Commands in this guide run from the repository root (`git clone` this repo and `cd` into it)._

```bash
recipes/gb10/vllm/docker-nemotron-3.5-lightning-nvfp4.sh --port 8000
curl -s http://localhost:8000/v1/models
```

For a pilot, one GB10 comfortably serves a small handful of concurrent
notebook users at intro-course concurrency (2–3 students per pool node is
the planning rule; see the README's inherited S-tier ladder).

Reasoning-model client rule: [Nemotron 3.5 Lightning](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4) is a reasoning model —
give client requests `max_tokens >= 512` or the budget is eaten by the
thinking trace.

## 2) Stand up JupyterHub on the same box

Use the official JupyterHub [Docker](https://www.docker.com/) image. Example minimal Compose:

```yaml
services:
  jupyterhub:
    image: jupyterhub/jupyterhub@sha256:15d50a67d5e898e16cfb44abefeda57e6330473408b99e170dc437e5286f5b58
    ports: ["8080:8000"]
    volumes:
      - ./jupyterhub_config.py:/srv/jupyterhub/jupyterhub_config.py:ro
      - /mnt/shared/students:/home/students     # NFS mount
    environment:
      - LOCAL_LLM_BASE_URL=http://host.docker.internal:8000/v1
      - LOCAL_LLM_MODEL=nvidia/nemotron-3.5-lightning
```

Point students' notebooks at the local endpoint via the `openai` Python
package:

```python
from openai import OpenAI
client = OpenAI(base_url="http://gb10-pilot.lab.university.edu:8000/v1", api_key="local")
resp = client.chat.completions.create(
    model="nvidia/nemotron-3.5-lightning",
    messages=[{"role":"user","content":"Explain gradient descent."}],
    max_tokens=1024,
)
print(resp.choices[0].message.content)
```

## 3) Add OpenWebUI (optional chat UI)

For students who prefer a chat interface rather than notebooks:

```yaml
services:
  openwebui:
    image: ghcr.io/open-webui/open-webui@sha256:4860ba005ae8f19f08d1e12b0868855b7b339ea0dad9927f196820fc0de04575
    ports: ["3000:8080"]
    environment:
      - OPENAI_API_BASE_URL=http://host.docker.internal:8000/v1
      - OPENAI_API_KEY=local
```

Students reach it at `http://<gb10-hostname>:3000`.

## 4) Per-seat setup (M tier exploration)

For the M tier, each student's GB10 runs its own [vLLM](https://github.com/vllm-project/vllm) (or Ollama) instance:

```bash
# Per-seat vLLM — the same recipe runs on every student workstation:
recipes/gb10/vllm/docker-nemotron-3.5-lightning-nvfp4.sh --port 8000

# Or Ollama as the developer quick-start on each seat:
ollama serve &
ollama pull <course-model>   # whichever lineup model the course pins

# Students use JupyterHub or OpenWebUI on localhost
```

Coding-heavy courses swap to the S-alt per seat:

```bash
recipes/gb10/vllm/docker-qwen3.8-27b-nvfp4.sh --port 8000
```

The application stack (Unsloth Studio, ComfyUI, [OpenCode](https://opencode.ai/)) installs as
per-student containers, backed by course-profile images pulled from the
shared model proxy / cache. For agent-workflow courses, each seat runs the
[NemoClaw](https://github.com/NVIDIA/NemoClaw) runtime stack per [OpenClaw on NemoClaw](../openclaw-on-nemoclaw/).

## 5) Shared compute for frontier / fine-tuning work (optional)

If you have a Dell Pro Precision with GB300 or a multi-GPU RTX PRO 6000 tower
available, stand up a shared vLLM instance for large-model workloads:

```bash
# GB300 — Lightning (M/L default Nemotron 3.5 Super VL: recipes/gb300/vllm/docker-nemotron-3.5-super-vl-nvfp4.sh):
recipes/gb300/vllm/docker-nemotron-3.5-lightning-nvfp4.sh --port 8000

# GB300 — L-tier alt (frontier dense-model assignments):
recipes/gb300/vllm/docker-glm-5.3-flash-nvfp4.sh --port 8000

# RTX PRO 6000 tower — M-tier alt (multi-instance or TP):
recipes/precision/vllm/docker-qwen3.8-flash-next-nvfp4.sh --port 8000
```

Front with [LiteLLM](https://www.litellm.ai/) to route course-specific requests to the appropriate
back-end — one endpoint URL for students, routing by course group.

## 6) VSS teaching module (video-understanding courses)

Classroom VSS uses public images only — the VLM ([Nemotron 3 Nano Omni](https://huggingface.co/nvidia/nemotron-3-nano-omni-30b-a3b)) and
LLM both serve as local vLLM endpoints, consumed by the upstream blueprint in
hybrid mode (`--use-remote-vlm --use-remote-llm`):

```bash
git clone https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization.git
# Serve VLM + LLM locally with vllm/vllm-openai containers, then bring up
# the VSS stack in dev-profile hybrid mode against those endpoints.
```

Detailed per-tier VSS sizing: [Agentic Video Search & Summarization](../agentic-vss/).

## Verify the pilot

- Log in as a test student.
- Open a JupyterHub notebook.
- Call the LLM endpoint from Python.
- Confirm you get a completion in < 1 s TTFT for a small prompt.

## What to observe during the pilot

These observations tune the pool sizing in the
[Solution overview](README.md#benchmarks-performance-validation):

- **Concurrency comfort** — how many students can run a notebook
  simultaneously at acceptable TTFT.
- **State reset speed** — how long between-class reset actually takes on
  your storage.
- **Storage growth** — model cache + student home directory growth per week.
- **Student experience** — is the local endpoint fast enough for the
  intended coursework?

## Related

- [Solution overview](README.md) — solution overview (sizing, models, S/M/L).
- [IT-Admin Guide](it-admin-guide.md) — full semester rollout playbook.
- [Agentic Coding](../agentic-coding/) — coding-agent course module
  (source of the S-tier concurrency ladder used for pool sizing).
- [Agentic Video Search & Summarization](../agentic-vss/) — video search & summarization module.
- [OpenClaw on NemoClaw](../openclaw-on-nemoclaw/) — agent-runtime course module.
- [Inference Stack & Models](../../docs/stack.md) — inference stack choices.
