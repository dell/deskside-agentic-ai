# Glossary

Each entry says what the term is and why it matters when you size, deploy or operate a solution.

## Solutions and sizing
| Term | Meaning | Why it matters |
|------|---------|----------------|
| **Solution (template)** | An open-source reference architecture and deployment guide for one use case, with S/M/L sizing; lives in [`solutions/`](../solutions/). | The unit you pick and deploy; every solution shares the same structure so they are comparable. |
| **S / M / L** | Sizing tiers mapped to Dell deskside systems (S = GB10 / T2, M = T4, L = GB300 / T6). See [S/M/L Sizing](sizing.md). | Lets you choose a scale (users, concurrency) without changing the stack. |
| **Dell Pro Precision (GB10)** | Dell deskside system powered by NVIDIA GB10 (Grace Blackwell, DGX Spark class), 128 GB unified memory, aarch64. | CPU and GPU share one memory pool, so every process on the box counts against model memory. |
| **Dell Pro Precision (GB300)** | High-end Dell deskside system powered by NVIDIA GB300 (252 GB HBM3e), aarch64. | The L-tier single-system option; fits the largest models and highest concurrency. |
| **Dell Pro Precision 9 T2 / T4 / T6** | Dell tower workstations powered by 1 / 2 / 5 × NVIDIA RTX PRO 6000 Blackwell GPUs. | Discrete GPUs connected over PCIe: shapes how multi-GPU serving (TP vs replicas) performs. |
| **Max-Q** | The lower-power (300 W) edition of the RTX PRO 6000 used in T4/T6. | Sustained throughput and thermals differ from the 600 W Workstation Edition in T2. |
| **Playbooks** | NVIDIA's open-source deployment guides (build.nvidia.com Spark, Station and RTX hubs) that solutions build on. | The upstream reference each solution starts from. |
| **Personas** | IT Admin, functional SME, AI engineer. See [Personas](personas.md). | Each guide is written for one of them. |
| **Seed-to-Scale** | The gap between evaluating AI on a workstation and operating it in production. | The reason each solution gives a path from one box to a fleet. |

## Serving and models
| Term | Meaning | Why it matters |
|------|---------|----------------|
| **[vLLM](https://github.com/vllm-project/vllm)** | Open-source LLM inference server with an OpenAI-compatible API. | The supported serving engine; clients just need a base URL, and its metrics feed the dashboards. |
| **NIM** | NVIDIA Inference Microservice, a containerized model server. | An alternative packaging for supported models. |
| **Nemotron** | NVIDIA's open model family (Lightning for S, Super VL for M/L). | The default model recommendation in every solution. |
| **NVFP4** | NVIDIA 4-bit floating-point quantization (about 4.5 bits per weight including scales). | Roughly quarters weight memory versus bf16, which is what lets 30B–120B models fit a deskside system. |
| **MoE (mixture of experts)** | A model where only some "expert" layers run per token (e.g. 30B total / 3B active). | Fast like a small model but all experts must still fit in memory, so size by total parameters. |
| **Reasoning model / reasoning parser** | A model that emits a thinking trace before the answer; the server separates it with a parser. | Small `max_tokens` budgets are consumed by thinking and return empty answers; use ≥ 512. |
| **Tool-call parser** | The server setting that turns the model's tool-call text into structured `tool_calls`. | Wrong or missing parser silently breaks agents; recipes set the right one per model. |
| **MTP / DFlash (speculative decoding)** | Extra draft heads or draft models that propose several tokens per step. | Raises single-stream speed; helps low concurrency more than high. |
| **Engram** | [Qwen3.8-Flash-Next](https://huggingface.co/nvidia/Qwen3.8-Flash-Next-NVFP4)'s large n-gram embedding table, offloaded to host RAM. | Explains its ≥ 128 GB host-RAM requirement. |
| **KV cache** | Per-request attention memory the server keeps while generating. | Limits context length times concurrency; "GPU KV cache size" in the server log is the real capacity. |
| **Prefix caching** | Reusing the KV cache of a shared prompt prefix. | Agents resend long histories; hits are free capacity (tracked on the dashboard). |
| **Context window (`--max-model-len`)** | The maximum prompt plus output tokens a recipe serves. | Clients must stay inside it or get errors; `recipes/lib/client-config.sh` derives safe limits. |
| **Unified memory** | GB10's single CPU+GPU memory pool. | `nvidia-smi` shows no GPU memory figure; use host memory tools. |
| **TP / DP / EP** | Tensor, data and expert parallelism: split one model across GPUs, run independent replicas, or spread MoE experts. | TP lowers latency per request; DP raises aggregate throughput. See [topology](topology.md). |
| **LiteLLM** | Open-source router/gateway that fronts several OpenAI-compatible backends. | Gives one endpoint over replicas, with keys, retries and failover. |

## Measurement
| Term | Meaning | Why it matters |
|------|---------|----------------|
| **[AIPerf](https://github.com/ai-dynamo/aiperf) (`aiperf`)** | NVIDIA's open-source benchmarking tool for OpenAI-compatible inference endpoints. | Used for measurement and sizing characterization: it drives a fixed synthetic workload at a chosen concurrency and reports throughput and latency, so numbers are repeatable and comparable across platforms. See [`tests/`](https://github.com/dell/deskside-agentic-ai/blob/main/tests/README.md). |
| **ISL / OSL** | Input / Output Sequence Length: prompt tokens in, tokens generated. | Sets the workload shape: short chat (200/200) and long-context agents (60k/1k) behave very differently, so every number is quoted with its shape. |
| **Concurrency (C)** | Number of requests in flight at once. | The x-axis of a capacity ladder; developer counts are derived from it. |
| **TTFT** | Time to first token. | The wait before anything appears; includes thinking tokens on reasoning models. |
| **ITL** | Inter-token latency. | Sets the streaming speed a user feels (1/ITL tok/s per session). |
| **Aggregate vs per-session tok/s** | Total output tokens per second across all sessions, versus aggregate divided by C. | Aggregate sizes the machine; per-session is what each user experiences and is compared with the responsiveness floor. |
| **Responsiveness floor** | Minimum per-session tok/s a user should see the Dell capacity tables size sessions at 20 tok/s. | The threshold that turns a concurrency ladder into a usable-session count. |
| **Tokenomics** | Token throughput and utilisation expressed as cost versus an equivalent cloud API. | The economics view of the platform; see [`monitoring/`](../monitoring/README.md). |

## Agents and operations
| Term | Meaning | Why it matters |
|------|---------|----------------|
| **[NemoClaw](https://github.com/NVIDIA/NemoClaw) / [OpenClaw](https://openclaw.ai/) / [OpenShell](https://github.com/NVIDIA/OpenShell)** | NVIDIA's agent runtime (NemoClaw) that onboards agents such as OpenClaw and Hermes Agent and runs them in OpenShell sandboxes. | Gives agents policy-bounded filesystem, network and subprocess access. |
| **Hermes Agent** | Nous Research's tool-using agent harness. | The agent the Hermes solution runs on NemoClaw. |
| **MCP** | Model Context Protocol for connecting agents to tools. | Tools run outside the sandbox with scoped credentials. |
| **Policy tier (strict / standard / permissive)** | NemoClaw sandbox policy presets. | Decides what an agent may touch; use standard in production. |
| **VSS** | NVIDIA's Video Search and Summarization blueprint. | The base of the video solution; needs its own LLM and VLM. |
| **Landscape** | Canonical's fleet-management service; script execution deploys recipes without SSH. | The documented way to roll recipes out to many machines. |
| **Readiness contract** | Every recipe blocks until the endpoint serves a real completion, then prints one `READY` line. | Automation and agents can trust "exit 0 means serving". |
