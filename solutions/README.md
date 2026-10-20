# Solution Catalog

Open-source reference architecture solutions for agentic AI on
Dell deskside systems powered by NVIDIA. Each follows a common structure
with S/M/L sizing, [vLLM](https://github.com/vllm-project/vllm)
config, deployment recipes, and validated performance, plus an IT-Admin guide.

## Solutions

| Solution | Category | Scope |
|----------|----------|-------|
| [Agentic Coding](agentic-coding/) | Horizontal | Private, on-deskside AI coding assistant — CLI/IDE agents behind an OpenAI-compatible API. Served with [Nemotron 3.5 Lightning](https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-NVFP4) by default on Dell deskside GPUs. |
| [Agentic Video Search & Summarization](agentic-vss/) | Vertical | Natural-language search, Q&A, and summarization over local video libraries — vision-language plus LLM serving on the same deskside tiers. |
| [OpenClaw on NemoClaw](openclaw-on-nemoclaw/) | Horizontal | The [OpenClaw](https://openclaw.ai/) assistant on NVIDIA's NemoClaw runtime — policy engine, [OpenShell](https://github.com/NVIDIA/OpenShell) sandbox, and tool-using agents on a locally served LLM. |
| [Hermes on NemoClaw](hermes-on-nemoclaw/) | Horizontal | [Nous Research](https://nousresearch.com/)' [Hermes Agent](https://hermes-agent.nousresearch.com/) harness on the [NemoClaw](https://github.com/NVIDIA/NemoClaw) runtime — served and sandboxed fully on Dell deskside hardware. |
| [Higher Education AI Lab](higher-ed-ai-lab/) | Vertical | Repeatable design for university AI teaching labs — shared serving tiers, per-course provisioning, and a curriculum built on the other solutions. |
