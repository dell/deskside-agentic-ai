#!/usr/bin/env python3
"""Minimal Canonical Landscape API client (stdlib only).

Auth: v2 REST API token via POST /api/v2/login/access-key (access_key + secret_key).
The same JWT is accepted by the legacy API (/api/?action=...) with
"Authorization: Bearer <jwt>", so no HMAC signing is needed.

Credentials are read from environment LANDSCAPE_ACCESS_KEY / LANDSCAPE_SECRET_KEY
(or LANDSCAPE_BASE for self-hosted Landscape) or from --access-key/--secret-key.

Usage:
  lapi.py login                       # refresh JWT cache, print token
  lapi.py computers                   # list managed computers
  lapi.py computer ID                 # computer details (with network devices)
  lapi.py get ACTION [k=v ...]        # any legacy API GET action
  lapi.py post ACTION [k=v ...]       # any legacy API POST action (form-encoded)
  lapi.py runscript --file SCRIPT --ids 1,2 [--title T] [--user root] [--limit 900]
                                      # CreateScript + ExecuteScript on computer ids
  lapi.py scriptout --id ACTIVITY_ID  # fetch script-run activity output
"""

import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get("LANDSCAPE_BASE", "https://landscape.canonical.com")
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".cache", "landscape_jwt")


def env_default(name, fallback=None):
    return os.environ.get(name, fallback)


def login(access_key, secret_key):
    body = json.dumps({"access_key": access_key, "secret_key": secret_key}).encode()
    req = urllib.request.Request(
        BASE + "/api/v2/login/access-key", data=body,
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.load(r)
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    fd = os.open(CACHE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(data["token"])
    return data


def cached_token():
    try:
        with open(CACHE) as f:
            return f.read().strip()
    except OSError:
        return None


def request(method, path, token, params=None, form=None, timeout=60):
    url = BASE + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    body = urllib.parse.urlencode(form).encode() if form else None
    req = urllib.request.Request(url, data=body, method=method,
                                 headers={"Authorization": "Bearer " + token})
    # Landscape SaaS occasionally 502s behind the load balancer; retry
    # transient failures so a multi-minute pollscript doesn't die mid-flight.
    import time
    last_err = None
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                raw = r.read().decode("utf-8", "replace")
            break
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8", "replace")
            if e.code in (401, 403) and attempt == 0:
                # Cached JWT expired mid-chain (login only fires when the cache
                # is ABSENT): refresh from credentials once, then retry.
                ak, sk = env_default("LANDSCAPE_ACCESS_KEY"), env_default("LANDSCAPE_SECRET_KEY")
                if ak and sk:
                    token = login(ak, sk)["token"]
                    req = urllib.request.Request(url, data=body, method=method,
                                                 headers={"Authorization": "Bearer " + token})
                    continue
            if e.code < 500:
                print("HTTP %d %s" % (e.code, raw), file=sys.stderr)
                raise SystemExit(2)
            last_err = "HTTP %d %s" % (e.code, raw[:200])
        except (urllib.error.URLError, TimeoutError) as e:
            last_err = "connect: %s" % e
        time.sleep(min(15 * (attempt + 1), 60))
    else:
        print("gave up after retries: %s" % last_err, file=sys.stderr)
        raise SystemExit(2)
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return raw


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--access-key", default=env_default("LANDSCAPE_ACCESS_KEY"))
    ap.add_argument("--secret-key", default=env_default("LANDSCAPE_SECRET_KEY"))
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("login")
    sub.add_parser("computers")
    c = sub.add_parser("computer"); c.add_argument("id", type=int)
    g = sub.add_parser("get"); g.add_argument("action"); g.add_argument("kvs", nargs="*")
    p = sub.add_parser("post"); p.add_argument("action"); p.add_argument("kvs", nargs="*")

    r = sub.add_parser("runscript")
    r.add_argument("--file", required=True, help="script file (must start with #!)")
    r.add_argument("--ids", required=True, help="comma-separated computer ids")
    r.add_argument("--title", default=None)
    r.add_argument("--user", default="root")
    r.add_argument("--limit", type=int, default=900, help="time_limit seconds")

    s = sub.add_parser("scriptout")
    s.add_argument("--id", type=int, help="activity id")
    s.add_argument("--recent", type=int, default=10, help="list recent activities")
    s.add_argument("--computer", type=int, help="filter activities by computer id")

    w = sub.add_parser("pollscript")
    w.add_argument("--group", type=int, required=True, help="ActivityGroup id from runscript")
    w.add_argument("--timeout", type=int, default=600, help="seconds to wait")

    ap.set_defaults()

    args = ap.parse_args()

    token = cached_token()

    def ensure_token():
        nonlocal token
        if args.cmd == "login" or not token:
            ak = args.access_key or env_default("LANDSCAPE_ACCESS_KEY")
            sk = args.secret_key or env_default("LANDSCAPE_SECRET_KEY")
            if not (ak and sk):
                raise SystemExit("no cached token and no credentials (export LANDSCAPE_ACCESS_KEY / LANDSCAPE_SECRET_KEY)")
            token = login(ak, sk)["token"]
        return token

    if args.cmd == "login":
        data = login(args.access_key, args.secret_key)
        print(json.dumps(data, indent=2))
        return

    if args.cmd == "computers":
        data = request("GET", "/api/v2/computers?limit=100", ensure_token())
        for comp in data.get("results", []):
            print("%-10d %-12s %-10s last_exchange=%s" % (
                comp["id"], comp["title"], comp["distribution"], comp.get("last_exchange_time")))
        return

    if args.cmd == "computer":
        data = request("GET", "/api/v2/computers/%d?with_network=true" % args.id, ensure_token())
        print(json.dumps(data, indent=2))
        return

    if args.cmd in ("get", "post"):
        form = dict(kv.split("=", 1) for kv in args.kvs)
        method = "GET" if args.cmd == "get" else "POST"
        q = {"action": args.action, "version": "2011-08-01"}
        if method == "GET":
            q.update(form)
            print(json.dumps(request("GET", "/api/", ensure_token(), params=q), indent=2))
        else:
            form.update({"action": args.action, "version": "2011-08-01"})
            print(json.dumps(request("POST", "/api/", ensure_token(), form=form), indent=2))
        return

    if args.cmd == "runscript":
        code = open(args.file, "rb").read()
        title = args.title or ("lapi-run-%s" % time.strftime("%Y%m%dT%H%M%S"))
        ids = [int(x) for x in args.ids.split(",")]
        created = request("POST", "/api/", ensure_token(), form={
            "action": "CreateScript", "version": "2011-08-01",
            "title": title,
            "time_limit": str(args.limit), "username": args.user,
            "code": base64.b64encode(code).decode()})
        script_id = created["id"] if isinstance(created, dict) else None
        if not script_id:
            raise SystemExit("CreateScript failed: %r" % (created,))
        print("script_id=%d title=%s" % (script_id, title))
        query = " OR ".join("id:%d" % i for i in ids)
        act = request("POST", "/api/", ensure_token(), form={
            "action": "ExecuteScript", "version": "2011-08-01",
            "query": query, "script_id": str(script_id), "username": args.user})
        print("activity:", json.dumps(act))
        return

    if args.cmd == "scriptout":
        tok = ensure_token()
        if args.id:
            data = request("GET", "/api/v2/activities/%d" % args.id, tok)
        else:
            q = "/api/v2/activities?limit=%d" % args.recent
            if args.computer:
                q += "&computer_id=%d" % args.computer
            data = request("GET", q, tok)
        print(json.dumps(data, indent=2))
        return

    if args.cmd == "pollscript":
        tok = ensure_token()
        deadline = time.time() + args.timeout
        seen = {}
        while time.time() < deadline:
            data = request("GET", "/api/v2/activities?limit=50", tok)
            res = data.get("results", data) if isinstance(data, dict) else data
            for a in res:
                if a.get("parent_id") == args.group:
                    seen[a["id"]] = a
            if seen and all(a.get("activity_status") in ("succeeded", "failed") for a in seen.values()):
                break
            time.sleep(5)
        for aid, a in sorted(seen.items()):
            comp = a.get("computer")
            cid = comp.get("id") if isinstance(comp, dict) else a.get("computer_id")
            print("\n===== activity %s computer=%s status=%s =====" % (aid, cid, a.get("activity_status")))
            print(a.get("result_text") or "")
        if not seen:
            print("no child activities seen for group", args.group)
        return


if __name__ == "__main__":
    main()
