# Choosing a serving topology (TP vs data-parallel) — per workload, by measurement

There is **no single right topology** for a multi-GPU Dell tower (T4 = 2 GPUs, T6 = 5). Tensor-parallel (TP) splits
one model across GPUs (lower per-request latency, one instance, but PCIe-only RTX PRO cards pay an all-reduce
penalty). Data-parallel (DP) runs independent replicas behind a router (best aggregate throughput when one GPU can hold
the model). Which wins depends on the model size, context length and workload shape — so it is **decided case by
case from measured results**, not by a rule of thumb.

## Procedure (per model × platform × workload shape)
1. **A — simplest:** one instance (TP = visible power-of-two GPUs):
   `recipes/<platform>/vllm/docker-<model>.sh` (health: `health-<model>.sh`).
2. **B — DP:** N replicas + LiteLLM front door (client endpoint stays `:8000`; replicas count up from `:8001`):
   ```bash
   recipes/lib/launch-replicas.sh --recipe recipes/precision/vllm/docker-nemotron-3.5-lightning-nvfp4.sh \
       --env-prefix NEMOTRON_LIGHTNING --served nvidia/nemotron-3.5-lightning --replicas 2   # or --gpu-groups "0,1 2,3"
   ```
   (Mixed layouts such as TP=2 × 2 replicas on four GPUs: `--gpu-groups "0,1 2,3"`.) PCIe-only towers: TP>1 needs
   `<PREFIX>_DISABLE_CUSTOM_AR=1` (see the recipe header).
3. **Measure the same shape on both** (never run two drivers at once; one topology up at a time):
   `tests/aiperf/sweep.sh --url http://localhost:8000 --model <served> --tokenizer <hf-id> --shape <shape> --ladder extended --platform <p>-<topology>`
   Use the shape that matches the workload (`chat_200_200`, `agent_60k_1k`, …, `tests/aiperf/shapes.yaml`).
4. **Decide:**
   ```bash
   python3 tests/aiperf/compare-topologies.py A/ladder.json B/ladder.json --shape agent_60k_1k --floor 20 --names TP2 DP2
   ```
   More usable sessions at your floor wins; within 5 % prefers the simpler topology (the first name). A ladder that ends
   before crossing the floor cannot win — extend it.
5. Record the winner (and the data folder) in `tests/data/<date>_<sha>/sizing.yaml`.

Until a workload has been measured, the recipe catalog does not name a final topology for it.

## LiteLLM front door
`recipes/lib/litellm.sh` renders `~/.deskside/litellm/config.yaml` (one `model_name`, every replica a deployment,
`least-busy` routing, retries + cooldown, pre-call context checks) and runs the pinned LiteLLM container with
`--num_workers` matched to the host cores (capped at 16 — a single-worker router capped an endpoint near 2.4k tok/s in
earlier measurements). Current LiteLLM refuses to start without a master key, so the launcher always has one
(`LITELLM_MASTER_KEY` or an auto-generated `~/.deskside/litellm/master-key`, mode 0600): **clients of the front door send it
as their API key.** Replicas bind to `127.0.0.1` behind it. Validated with two TP=2 replicas on a T6 tower (chat and agent shapes) and with mock replicas including failover
(`tests/test_recipe_contract.sh`).
