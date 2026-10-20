# Fleet deployment via Canonical Landscape (OpenClaw on NemoClaw)

Roll OpenClaw on NemoClaw out to a fleet of enrolled Ubuntu systems (Dell deskside systems powered by NVIDIA) from
[Canonical Landscape](https://ubuntu.com/landscape), with no SSH, logged in the Landscape activity feed and repeatable from CI.
The enrolment, script-execution, verification and close-out steps are the same for every solution and are described once in
[Fleet Deploy via Landscape (Agentic Coding)](../agentic-coding/landscape-fleet-deploy.md); this page adds what is specific here.

## Steps

1. **Enable script execution** on the target devices (Step 1 of the common guide, root, once per rollout window).
2. **Stage** this repository on each device at `/opt/deskside-agentic-ai-solutions-for-nvidia` (file transfer only).
3. **Deploy** with the solution payload:

```bash
export SOLUTION=openclaw
python3 scripts/landscape/landscape_client.py runscript \
  --file scripts/landscape/deploy-solution.sh --ids "$ID" --user root --limit 3000
python3 scripts/landscape/landscape_client.py pollscript --group <group-id> --timeout 3200
```

   The payload runs the serving recipe first (nvidia runtime self-heal, pinned image, readiness contract), then the solution step,
   and exits non-zero unless the solution is actually up. Variables: `NEMOCLAW_INSTALLER_SHA256` (required pin of NVIDIA's installer), `AGENT_USER` (account that owns the runtime, default `dell`; it is added to the `docker` group), `LLM_MODEL` (default: the first model the local endpoint serves), `SANDBOX_NAME`, `DESKSIDE_API_KEY`, `NEMOCLAW_INSTALL_REF` (pin the NemoClaw release).
4. **Verify** (Step 3 of the common guide, `scripts/landscape/verify-serving.sh`) and confirm `openshell status` is healthy on the device, the sandbox lists as `Ready`, and a prompt sent from inside the sandbox reaches the local endpoint at `http://host.docker.internal:8000/v1`.
5. **Close root script execution** (Step 4 of the common guide, `scripts/landscape/disable-script-execution.sh`) once the fleet is healthy.

## Notes

* Onboarding runs through NemoClaw's own non-interactive mode, pointed at the local OpenAI-compatible endpoint (`NEMOCLAW_PROVIDER=custom`), so no wizard is needed and no answers file has to be captured.
* Plane 2 installs from NVIDIA's shipping installer. The payload fetches it to a file and refuses to run it unless its sha256 matches your pin.
* Roll out in waves (one tagged canary first); sandboxes keep running while the serving container is replaced.

## Rollback and teardown

Re-run the deploy with the previous image digest from `recipes/versions.lock`, or remove the containers with a one-line payload
(`docker rm -f <container>`; `docker compose down -v` for compose-based solutions). Re-enable script execution first if it has been closed.
