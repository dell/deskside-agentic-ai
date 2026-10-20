#!/bin/bash
# Close the root script-execution channel after a rollout (run on the device, with sudo).
# Landscape ScriptExecution runs payloads as the users listed in `script_users` (root for deploys).
# Root is only needed while deploying/verifying: afterwards remove the plugin and the users so the
# device keeps reporting/patching but can no longer be told to run scripts. Re-enable (enable-script-execution.sh)
# for the next rollout window.
#   sudo scripts/landscape/disable-script-execution.sh            # edits /etc/landscape/client.conf
#   LANDSCAPE_CONF=/tmp/test.conf scripts/landscape/disable-script-execution.sh --no-restart   # dry test on a copy
# Does NOT re-register the machine (no landscape-config), so the computer id and approval state are kept.
set -euo pipefail
CONF="${LANDSCAPE_CONF:-/etc/landscape/client.conf}"
RESTART=1; [ "${1:-}" = "--no-restart" ] && RESTART=0
[ -f "$CONF" ] || { echo "no $CONF (is landscape-client installed?)" >&2; exit 2; }
cp -p "$CONF" "$CONF.bak-$(date +%Y%m%d%H%M%S)"
python3 - "$CONF" <<'PY'
import configparser, sys
p = sys.argv[1]; c = configparser.ConfigParser(interpolation=None); c.optionxform = str; c.read(p)
if "client" not in c: c.add_section("client")
plugins = [x.strip() for x in c["client"].get("include_manager_plugins", "").split(",") if x.strip()]
plugins = [x for x in plugins if x != "ScriptExecution"]
c["client"]["include_manager_plugins"] = ", ".join(plugins)
c["client"]["script_users"] = ""
with open(p, "w") as f: c.write(f)
print("ScriptExecution removed; include_manager_plugins =", c["client"]["include_manager_plugins"] or "(none)", "| script_users cleared")
PY
if [ "$RESTART" = 1 ]; then systemctl restart landscape-client && echo "landscape-client restarted"; fi
grep -E "^(include_manager_plugins|script_users)" "$CONF" || true
