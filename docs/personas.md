# Personas

Solutions apply an **IT Admin + functional SME + AI engineer** lens to NVIDIA's
developer-focused reference materials. Every solution states how it serves each
persona.

## IT Admin

- **Cares about:** system setup, drivers/OS, containerized deployment, fleet
  management, identity (AD/LDAP), monitoring, scaling dev→prod, security.
- **Solution gives them:** step-by-step setup, management-environment config,
  and fleet/scaling guidance.


## Functional SME

- **Cares about:** does this use case fit my workflow? what scale/quality should
  I expect? what does "good" look like?
- **Solution gives them:** the use-case framing, S/M/L scale guidance (user
  counts, expected performance), and validation results.

## AI Engineer

- **Cares about:** model choice, quantization, inference stack tuning, context
  length, throughput/latency, integration (OpenAI-compatible API, tools).
- **Solution gives them:** per-tier / per-workload model recommendations
  (Nemotron-family primary + measured alternatives — the [stack guide](stack/)
  is the source of truth for tier-specific winners), [vLLM](https://github.com/vllm-project/vllm) configuration,
  reference code/config, and aiperf benchmarks.

## Mapping to solution sections

| Persona | Primary solution sections |
|---------|---------------------------|
| IT Admin | Deployment (IT-Admin guide), Management environment |
| Functional SME | Summary, S/M/L sizing, Validation |
| AI Engineer | Model recommendation, Inference stack, Architecture, Validation |
