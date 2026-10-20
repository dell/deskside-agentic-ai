# Fleet deployment via Canonical Landscape (Agentic Video Search & Summarization)

Roll Agentic Video Search & Summarization out to a fleet of enrolled Ubuntu systems (Dell deskside systems powered by NVIDIA) from
[Canonical Landscape](https://ubuntu.com/landscape), with no SSH, logged in the Landscape activity feed and repeatable from CI.
The enrolment, script-execution, verification and close-out steps are the same for every solution and are described once in
[Fleet Deploy via Landscape (Agentic Coding)](../agentic-coding/landscape-fleet-deploy.md); this page adds what is specific here.

## Steps

1. **Enable script execution** on the target devices (Step 1 of the common guide, root, once per rollout window).
2. **Stage** this repository on each device at `/opt/deskside-agentic-ai-solutions-for-nvidia` (file transfer only).
3. **Deploy** with the solution payload:

```bash
export SOLUTION=vss
python3 scripts/landscape/landscape_client.py runscript \
  --file scripts/landscape/deploy-solution.sh --ids "$ID" --user root --limit 3000
python3 scripts/landscape/landscape_client.py pollscript --group <group-id> --timeout 3200
```

   The payload runs the serving recipe first (nvidia runtime self-heal, pinned image, readiness contract), then the solution step,
   and exits non-zero unless the solution is actually up. Variables: `VSS_COMPOSE_FILE` (the VSS blueprint compose project already staged on the device), `VSS_HEALTH_URL` (default `http://localhost:7777`).
4. **Verify** (Step 3 of the common guide, `scripts/landscape/verify-serving.sh`) and confirm the Agent UI answers on `:7777`, the serving endpoint lists its model on `:8000` (start recipes with `DESKSIDE_BASE_PORT=8100` when VSS owns `:8000`), and `docker compose ps` shows every VSS service running.
5. **Close root script execution** (Step 4 of the common guide, `scripts/landscape/disable-script-execution.sh`) once the fleet is healthy.

## Notes

* VSS needs NGC credentials and the blueprint compose project on the device. Stage them as files (not on the command line) and point `VSS_COMPOSE_FILE` at them.
* The blueprint runs its own LLM and VLM; budget GPU memory with the co-tenancy rules in [Operations](../../docs/operations.md).
* The Docker engine must be inside the version window the blueprint supports; check it before the rollout.

## Rollback and teardown

Re-run the deploy with the previous image digest from `recipes/versions.lock`, or remove the containers with a one-line payload
(`docker rm -f <container>`; `docker compose down -v` for compose-based solutions). Re-enable script execution first if it has been closed.
