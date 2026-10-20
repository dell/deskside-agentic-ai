# Fleet deployment via Canonical Landscape (Higher Education AI Lab)

Roll Higher Education AI Lab out to a fleet of enrolled Ubuntu systems (Dell deskside systems powered by NVIDIA) from
[Canonical Landscape](https://ubuntu.com/landscape), with no SSH, logged in the Landscape activity feed and repeatable from CI.
The enrolment, script-execution, verification and close-out steps are the same for every solution and are described once in
[Fleet Deploy via Landscape (Agentic Coding)](../agentic-coding/landscape-fleet-deploy.md); this page adds what is specific here.

## Steps

1. **Enable script execution** on the target devices (Step 1 of the common guide, root, once per rollout window).
2. **Stage** this repository on each device at `/opt/deskside-agentic-ai-solutions-for-nvidia` (file transfer only).
3. **Deploy** with the solution payload:

```bash
export SOLUTION=higher-ed
python3 scripts/landscape/landscape_client.py runscript \
  --file scripts/landscape/deploy-solution.sh --ids "$ID" --user root --limit 3000
python3 scripts/landscape/landscape_client.py pollscript --group <group-id> --timeout 3200
```

   The payload runs the serving recipe first (nvidia runtime self-heal, pinned image, readiness contract), then the solution step,
   and exits non-zero unless the solution is actually up. Variables: `COURSE_COMPOSE` (course profile compose file), plus the serving variables (`RECIPE`, `CONTAINER`) per tier.
4. **Verify** (Step 3 of the common guide, `scripts/landscape/verify-serving.sh`) and confirm each seat's endpoint lists its model, the course stack is running, and the seat reports under its course and term tags in Landscape.
5. **Close root script execution** (Step 4 of the common guide, `scripts/landscape/disable-script-execution.sh`) once the fleet is healthy.

## Notes

* **Large assets:** for images, models and datasets that every seat needs, use multicast distribution instead of unicast pulls; see [Bulk distribution over the LAN](it-admin-guide.md#bulk-distribution-over-the-lan-multicast).
* Target by tag (`course-<id>`, `term-<yyyy-s>`) so one dispatch configures a whole room.
* **Between classes** dispatch `reset-seat.sh`: it flushes log shipping, takes the read-only home snapshot, brings the course stack down with its volumes, restores the baseline and starts it again. It refuses to wipe when the flush or snapshot fails, so the audit trail is never lost to a reset.
* Close root script execution after the term rollout (Step 4) and re-open it only for the next maintenance window; see [Network and endpoint security](it-admin-guide.md#network-and-endpoint-security).

## Rollback and teardown

Re-run the deploy with the previous image digest from `recipes/versions.lock`, or remove the containers with a one-line payload
(`docker rm -f <container>`; `docker compose down -v` for compose-based solutions). Re-enable script execution first if it has been closed.
