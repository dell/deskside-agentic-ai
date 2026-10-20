#!/bin/bash
# Fleet verify payload (dispatched as root via Landscape ScriptExecution).
# Loops INTERNALLY so the whole check costs ONE Landscape exchange cycle
# (script results otherwise arrive 15-30 min late on busy clients).
# Prints a heartbeat, weight-download progress, and on green: model listing +
# one smoke completion. Exits early if the container dies (with log tail).
#
# Env: PORT (default 8000), CONTAINER (default lightning-3.5-gb10),
#      MODEL (served alias, default nemotron-lightning),
#      WEIGHTS (HF cache dir for the progress line, optional)
PORT="${PORT:-8000}"
CONTAINER="${CONTAINER:-lightning-3.5-gb10}"
MODEL="${MODEL:-nemotron-lightning}"
WEIGHTS="${WEIGHTS:-}"
LOOPS="${VERIFY_ITERS:-80}"
for i in $(seq 1 "$LOOPS"); do
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 "http://localhost:$PORT/health")
    st=$(docker ps -a --filter "name=$CONTAINER" --format "{{.Status}}" | head -1)
    dl=$(du -sm "$WEIGHTS" 2>/dev/null | cut -f1)
    echo "$(date +%H:%M:%S) health=$code weights=${dl:-?}MB [$st]"
    if [ "$code" = 200 ]; then
        echo READY
        curl -s "http://localhost:$PORT/v1/models" | head -c 300; echo
        curl -s "http://localhost:$PORT/v1/chat/completions" -H "Content-Type: application/json" \
          -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: FLEET DEPLOY OK\"}],\"max_tokens\":512,\"temperature\":0}" \
          | python3 -c 'import json,sys; r=json.load(sys.stdin); print("smoke:", (r["choices"][0]["message"].get("content") or "").strip()[:120])'
        exit 0
    fi
    echo "$st" | grep -qiE "exited|dead" && { echo DIED; docker logs --tail 15 "$CONTAINER" 2>&1 | tail -8; exit 1; }
    sleep 30
done
echo "TIMEOUT: not healthy within ~$(( LOOPS / 2 )) min"
exit 2
