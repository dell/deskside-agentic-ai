#!/bin/bash
# Between-class reset for a lab seat (Higher-Ed AI Lab). Dispatch as root via Landscape ScriptExecution, scoped by tag
# (for example course-cs101). It preserves the audit trail, then returns the seat to a known state.
#   COURSE_COMPOSE   course profile compose file               (required)
#   SNAPSHOT_CMD     command that takes a read-only snapshot of student homes before the wipe (optional; example:
#                    "zfs snapshot tank/home@$(date +%Y%m%d%H%M)" or your NAS API call)
#   FLUSH_CMD        command that flushes log shipping (optional; example: "systemctl kill -s HUP rsyslog")
#   RESTORE_CMD      command that restores the golden home/image state (optional)
set -uo pipefail
: "${COURSE_COMPOSE:?set COURSE_COMPOSE}"
[ -n "${FLUSH_CMD:-}" ] && { bash -c "$FLUSH_CMD" || { echo "LOG FLUSH FAILED - not resetting"; exit 1; }; }
[ -n "${SNAPSHOT_CMD:-}" ] && { bash -c "$SNAPSHOT_CMD" || { echo "SNAPSHOT FAILED - not resetting"; exit 1; }; }
docker compose -f "$COURSE_COMPOSE" down -v
docker container prune -f >/dev/null
[ -n "${RESTORE_CMD:-}" ] && bash -c "$RESTORE_CMD"
docker compose -f "$COURSE_COMPOSE" up -d
sleep 5
[ -n "$(docker compose -f "$COURSE_COMPOSE" ps --status running -q)" ] && echo "RESET-OK: seat back to course baseline" || { echo "COURSE STACK NOT UP AFTER RESET"; exit 1; }
