#!/usr/bin/env python3
"""Authenticated client for the validator BYOSnap behind the Snapser gateway.

Anonymous-logs-in via the Auth snap to obtain a user session token, caches it in a
dotfile, and calls the validator with the `Token` / `User-Id` headers the gateway expects.

Config resolution (first wins):
  1. env vars: SNAPSER_GATEWAY, SNAPSER_VALIDATOR_PREFIX, SNAPSER_ANON_USERNAME
  2. ~/.snapser/validator.json  {"gateway":..., "snap_prefix":..., "username":...}
  3. built-in defaults (dev snapend c4n1awfs)

Session cache: ~/.snapser/validator-session.json (chmod 600; gitignored by living in $HOME).

Usage:
  client.py login [--username NAME] [--force]
  client.py token
  client.py call METHOD PATH [--body JSON] [--no-auto-login]
  client.py smoke
"""
import argparse, json, os, sys, time, urllib.request, urllib.error

HOME = os.path.expanduser("~")
CFG_PATH = os.path.join(HOME, ".snapser", "validator.json")
SESSION_PATH = os.path.join(HOME, ".snapser", "validator-session.json")

DEFAULTS = {
    "gateway": "https://gateway.snapser.com/c4n1awfs",
    "snap_prefix": "/v1/byosnap-validator",
    "username": "validator-dev-client",
}


def load_config():
    cfg = dict(DEFAULTS)
    if os.path.exists(CFG_PATH):
        try:
            cfg.update({k: v for k, v in json.load(open(CFG_PATH)).items() if v})
        except Exception as e:
            print(f"warning: could not read {CFG_PATH}: {e}", file=sys.stderr)
    cfg["gateway"] = os.environ.get("SNAPSER_GATEWAY", cfg["gateway"]).rstrip("/")
    cfg["snap_prefix"] = os.environ.get("SNAPSER_VALIDATOR_PREFIX", cfg["snap_prefix"])
    cfg["username"] = os.environ.get("SNAPSER_ANON_USERNAME", cfg["username"])
    return cfg


def _request(method, url, headers=None, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        r = urllib.request.urlopen(req, timeout=30)
        return r.status, r.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")
    except Exception as e:
        return 0, f"request error: {e}"


def save_session(sess):
    os.makedirs(os.path.dirname(SESSION_PATH), exist_ok=True)
    with open(SESSION_PATH, "w") as f:
        json.dump(sess, f, indent=2)
    os.chmod(SESSION_PATH, 0o600)


def load_session():
    if os.path.exists(SESSION_PATH):
        try:
            return json.load(open(SESSION_PATH))
        except Exception:
            return None
    return None


def login(cfg, username=None, force=False):
    if not force:
        s = load_session()
        if s and s.get("session_token") and s.get("expires_at", 0) > time.time() + 30:
            return s
    user = username or cfg["username"]
    url = f"{cfg['gateway']}/v1/auth/login/anon"
    status, body = _request("PUT", url, body={"username": user, "create_user": True})
    if status != 200:
        print(f"login failed ({status}): {body}", file=sys.stderr)
        if "not enabled" in body.lower():
            print("\nThe Anonymous connector is not enabled on this snapend's Auth snap.\n"
                  "Enable it in the Snapser dashboard (Auth snap -> Connectors -> Anonymous),\n"
                  "redeploy the snapend, then retry.", file=sys.stderr)
        sys.exit(1)
    u = json.loads(body).get("user", {})
    ttl = int(u.get("token_validity_seconds") or 0)
    sess = {
        "user_id": u.get("id"),
        "session_token": u.get("session_token"),
        "expires_at": int(time.time()) + (ttl if ttl > 0 else 3600),
        "username": user,
    }
    save_session(sess)
    return sess


def auth_headers(sess):
    return {"Token": sess["session_token"], "User-Id": sess["user_id"]}


def call(cfg, method, path, body=None, auto_login=True):
    sess = load_session()
    if not sess or not sess.get("session_token"):
        if not auto_login:
            print("no session; run `login` first", file=sys.stderr); sys.exit(1)
        sess = login(cfg)
    if not path.startswith("/"):
        path = "/" + path
    url = f"{cfg['gateway']}{cfg['snap_prefix']}{path}"
    status, resp = _request(method.upper(), url, headers=auth_headers(sess), body=body)
    # one retry if the token went stale
    if status in (400, 401) and auto_login and ("token" in resp.lower() or "session" in resp.lower()):
        sess = login(cfg, force=True)
        status, resp = _request(method.upper(), url, headers=auth_headers(sess), body=body)
    return status, resp


def main():
    cfg = load_config()
    ap = argparse.ArgumentParser(description="Validator BYOSnap authenticated client")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p_login = sub.add_parser("login"); p_login.add_argument("--username"); p_login.add_argument("--force", action="store_true")
    sub.add_parser("token")
    p_call = sub.add_parser("call")
    p_call.add_argument("method"); p_call.add_argument("path")
    p_call.add_argument("--body"); p_call.add_argument("--no-auto-login", action="store_true")
    sub.add_parser("smoke")
    args = ap.parse_args()

    if args.cmd == "login":
        s = login(cfg, username=args.username, force=args.force)
        print(f"logged in as user_id={s['user_id']} (token cached at {SESSION_PATH})")
    elif args.cmd == "token":
        s = load_session()
        print(s["session_token"] if s and s.get("session_token") else "(no session; run login)")
    elif args.cmd == "call":
        body = json.loads(args.body) if args.body else None
        status, resp = call(cfg, args.method, args.path, body=body, auto_login=not args.no_auto_login)
        print(f"HTTP {status}")
        print(resp)
        sys.exit(0 if 200 <= status < 300 else 1)
    elif args.cmd == "smoke":
        print(f"gateway: {cfg['gateway']}{cfg['snap_prefix']}")
        login(cfg)
        ok = True
        for m, p in [("GET", "/health"), ("GET", "/api/status"), ("GET", "/")]:
            status, resp = call(cfg, m, p)
            mark = "OK " if 200 <= status < 300 else "ERR"
            print(f"[{mark}] {m} {p} -> {status}  {resp[:100].strip()}")
            ok = ok and 200 <= status < 300
        print("\nSMOKE PASS" if ok else "\nSMOKE FAIL")
        sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
