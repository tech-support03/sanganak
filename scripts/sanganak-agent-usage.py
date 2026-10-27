#!/usr/bin/env python3
"""sanganak-agent-usage — write AI coding agent usage records for the bar.

One JSON record per agent lands in ~/.local/state/sanganak/agents/<id>.json;
services/Agents.qml watches that directory. An agent with no local usage
writes nothing, so the bar icon stays hidden on a machine that never ran one.

claude  limits: Anthropic's OAuth usage endpoint (5-hour session + 7-day),
                using the Claude Code CLI's own login. No login → local stats
                only, with `authError` set.
        local:  ~/.claude/projects/**/*.jsonl assistant turns (deduped by
                message id + request id), last 7 days.
codex   limits: the newest `rate_limits` seen in a session file.
        local:  ~/.codex/sessions/**/rollout-*.jsonl token_count events.

Record: { id, name, plan, ready, authError, limits: [{label, percent 0..1,
resetsAt ISO}], days: [{date, tokens}] (7, oldest first), models: {model:
{input, output, cacheRead, cacheWrite}}, todayTokens, todaySessions }
"""
import datetime as dt
import json
import os
import sys
import time
import urllib.request
from pathlib import Path

HOME = Path.home()
OUT = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "sanganak" / "agents"
DAYS = 7


def window():
    today = dt.date.today()
    return [today - dt.timedelta(days=i) for i in range(DAYS - 1, -1, -1)]


def local_date(ts):
    try:
        return dt.datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().date()
    except (ValueError, AttributeError):
        return None


def recent_files(root, pattern):
    cutoff = time.time() - (DAYS + 1) * 86400
    if not root.is_dir():
        return []
    return [p for p in root.rglob(pattern) if p.stat().st_mtime >= cutoff]


def write(record):
    OUT.mkdir(parents=True, exist_ok=True)
    tmp = OUT / (record["id"] + ".json.tmp")
    tmp.write_text(json.dumps(record, indent=1))
    tmp.replace(OUT / (record["id"] + ".json"))


def empty_record(agent_id, name):
    days = window()
    return {"id": agent_id, "name": name, "plan": "", "ready": True, "authError": "",
            "limits": [], "days": [{"date": d.isoformat(), "tokens": 0} for d in days],
            "models": {}, "todayTokens": 0, "todaySessions": 0}


def add_usage(rec, day, model, inp, out, cread, cwrite, session):
    total = inp + out + cread + cwrite
    for d in rec["days"]:
        if d["date"] == day.isoformat():
            d["tokens"] += total
    m = rec["models"].setdefault(model or "unknown", {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0})
    m["input"] += inp
    m["output"] += out
    m["cacheRead"] += cread
    m["cacheWrite"] += cwrite
    if day == dt.date.today():
        rec["todayTokens"] += total
        rec.setdefault("_sessions", set()).add(session)


# ---- claude -------------------------------------------------------------------

def claude_limits(rec):
    cred_path = Path(os.environ.get("CLAUDE_CONFIG_DIR", HOME / ".claude")) / ".credentials.json"
    try:
        login = json.loads(cred_path.read_text()).get("claudeAiOauth") or {}
    except (OSError, ValueError):
        login = {}
    token = login.get("accessToken") or ""
    rec["plan"] = {"max": "Max", "pro": "Pro", "team": "Team", "enterprise": "Enterprise"}.get(
        str(login.get("subscriptionType") or "").lower(), str(login.get("subscriptionType") or ""))
    if not token:
        rec["authError"] = "Run `claude auth login` to see limits."
        return
    req = urllib.request.Request("https://api.anthropic.com/api/oauth/usage", headers={
        "Authorization": "Bearer " + token,
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "sanganak-agent-usage",
    })
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            payload = json.load(resp)
    except Exception as e:  # network down, expired token, endpoint change
        code = getattr(e, "code", None)
        rec["authError"] = "Sign in again: `claude auth login`." if code in (401, 403) else "Limits unavailable right now."
        return
    raw = []
    for key, label in (("five_hour", "Session (5-hour)"), ("seven_day", "Weekly (7-day)")):
        b = payload.get(key)
        if isinstance(b, dict) and b.get("utilization") is not None:
            raw.append((label, float(b["utilization"]), b.get("resets_at") or ""))
    # The endpoint has reported both 0..1 and 0..100; any value ≥ 1 means percent.
    scale = 100.0 if any(v >= 1 for _, v, _ in raw) else 1.0
    rec["limits"] = [{"label": l, "percent": min(1.0, v / scale), "resetsAt": r} for l, v, r in raw]


def claude():
    root = Path(os.environ.get("CLAUDE_CONFIG_DIR", HOME / ".claude")) / "projects"
    files = recent_files(root, "*.jsonl")
    rec = empty_record("claude", "Claude Code")
    first = window()[0]
    seen = set()
    any_usage = False
    for f in files:
        try:
            lines = f.open(encoding="utf-8", errors="replace")
        except OSError:
            continue
        with lines:
            for line in lines:
                if '"usage"' not in line:
                    continue
                try:
                    e = json.loads(line)
                except ValueError:
                    continue
                msg = e.get("message") or {}
                u = msg.get("usage")
                day = local_date(e.get("timestamp", ""))
                if not u or not day or day < first:
                    continue
                key = (msg.get("id"), e.get("requestId"))
                if key in seen:
                    continue
                seen.add(key)
                any_usage = True
                add_usage(rec, day, msg.get("model"), u.get("input_tokens", 0) or 0, u.get("output_tokens", 0) or 0,
                          u.get("cache_read_input_tokens", 0) or 0, u.get("cache_creation_input_tokens", 0) or 0,
                          e.get("sessionId") or str(f))
    if not any_usage and not (HOME / ".claude").is_dir():
        return None
    claude_limits(rec)
    return rec


# ---- codex --------------------------------------------------------------------

def codex():
    root = Path(os.environ.get("CODEX_HOME", HOME / ".codex")) / "sessions"
    files = sorted(recent_files(root, "rollout-*.jsonl"), key=lambda p: p.stat().st_mtime)
    if not files:
        return None
    rec = empty_record("codex", "Codex")
    first = window()[0]
    newest_limits = None
    for f in files:
        model = None
        try:
            lines = f.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for line in lines:
            try:
                e = json.loads(line)
            except ValueError:
                continue
            p = e.get("payload") or {}
            if e.get("type") == "turn_context":
                model = p.get("model") or model
            if p.get("type") != "token_count":
                continue
            if p.get("rate_limits"):
                newest_limits = p["rate_limits"]
            last = (p.get("info") or {}).get("last_token_usage") or {}
            day = local_date(e.get("timestamp", ""))
            if not last or not day or day < first:
                continue
            cached = last.get("cached_input_tokens", 0) or 0
            add_usage(rec, day, model, max(0, (last.get("input_tokens", 0) or 0) - cached),
                      last.get("output_tokens", 0) or 0, cached, 0, str(f))
    if newest_limits:
        for key, label in (("primary", "Session (5-hour)"), ("secondary", "Weekly (7-day)")):
            b = newest_limits.get(key)
            if not isinstance(b, dict) or b.get("used_percent") is None:
                continue
            resets = b.get("resets_at")
            if isinstance(resets, (int, float)):
                resets = dt.datetime.fromtimestamp(resets, dt.timezone.utc).isoformat()
            rec["limits"].append({"label": label, "percent": min(1.0, float(b["used_percent"]) / 100.0),
                                  "resetsAt": resets or ""})
    return rec


def main():
    wanted = set(sys.argv[1:])
    for agent_id, collect in (("claude", claude), ("codex", codex)):
        if wanted and agent_id not in wanted:
            continue
        try:
            rec = collect()
        except Exception as e:  # one broken collector must not stop the other
            print(f"{agent_id}: {e}", file=sys.stderr)
            continue
        if rec is None:
            continue
        rec["todaySessions"] = len(rec.pop("_sessions", ()))
        write(rec)


if __name__ == "__main__":
    main()
