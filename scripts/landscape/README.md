# scripts/landscape — Canonical Landscape fleet automation

Stdlib-only tooling to deploy and verify this solution's serving recipes
across a fleet of enrolled Ubuntu machines (DGX Spark / Precision / DGX
Station) **without SSH**: [Landscape](https://ubuntu.com/landscape)'s ScriptExecution plugin is the execution
channel, so fleet changes stay visible in the Landscape activity log.

| File | Where it runs | Purpose |
|------|---------------|---------|
| `landscape_client.py` | your control host | API client (JWT via `POST /api/v2/login/access-key`; the same token works on the legacy `/api/` service — no HMAC needed). Subcommands: `login`, `computers`, `runscript`, `pollscript`, `get`/`post` for any API action. |
| `enable-script-execution.sh` | device (sudo, once) | Turns on the ScriptExecution manager plugin. **Re-registration caveat** inside. |
| `fix-docker-nvidia-runtime.sh` | device (root) | One-shot fix for `unknown or invalid runtime name: nvidia` on stock images. |
| `deploy-serving-recipe.sh` | device (root) | Payload: runtime fix (self-heal) → image pre-pull → recipe → hard gate (`exit 1` unless the container is up). |
| `verify-serving.sh` | device (root) | Payload: self-looping health/models/smoke check — one exchange cycle, not twenty. |

Setup:

```bash
export LANDSCAPE_ACCESS_KEY=... LANDSCAPE_SECRET_KEY=...   # Landscape > Profile > API
export LANDSCAPE_BASE=https://landscape.canonical.com      # or your self-hosted URL
python3 scripts/landscape/landscape_client.py login
```

Full procedure with expectations and gotchas:
[`solutions/agentic-coding/landscape-fleet-deploy.md`](../../solutions/agentic-coding/landscape-fleet-deploy.md).
