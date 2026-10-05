#!/usr/bin/env python3
"""Read a worker's own transcript: Claude Code (projects/*/<session>.jsonl) or Codex (rollout files).

  transcript.py find KIND SESSION [--cwd DIR --since EPOCH]   path of the transcript, or nothing
  transcript.py reply KIND PATH          the replies since the last real prompt
  transcript.py prompts KIND PATH        how many real prompts it holds
  transcript.py news KIND PATH MARK      CHECKIN / COMPACTED among lines appended since MARK (an offset file)
  transcript.py context KIND PATH        tokens in the last reply's context
  transcript.py size KIND PATH           bytes, for progress fingerprints

KIND is claude or codex; any other kind has no transcript and `find` prints nothing.
--cwd/--since find a Codex session Herdr has not reported yet: the newest rollout started in DIR
after EPOCH.
"""
import glob
import json
import os
import sys

CLAUDE = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
CODEX = os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex")
TAIL = 4_000_000


def find(kind, session, cwd=None, since=None):
    if kind == "claude" and session not in ("", "-"):
        hits = glob.glob(os.path.join(CLAUDE, "projects", "*", f"{session}.jsonl"))
        return hits[0] if hits else ""
    if kind == "codex":
        if session not in ("", "-"):
            hits = glob.glob(os.path.join(CODEX, "sessions", "*", "*", "*", f"rollout-*{session}.jsonl"))
            if hits:
                return hits[0]
        if cwd and since is not None:
            real = os.path.realpath(cwd)
            files = sorted(glob.glob(os.path.join(CODEX, "sessions", "*", "*", "*", "rollout-*.jsonl")),
                           key=os.path.getmtime, reverse=True)
            for f in files[:40]:
                if os.path.getmtime(f) < since:
                    break
                meta = first_entry(f)
                if meta.get("type") == "session_meta" and os.path.realpath(meta["payload"].get("cwd", "")) == real:
                    return f
    return ""


def first_entry(path):
    try:
        with open(path, "rb") as fh:
            return json.loads(fh.readline())
    except (OSError, ValueError):
        return {}


def entries(path):
    size = os.path.getsize(path)
    with open(path, "rb") as fh:
        fh.seek(max(0, size - TAIL))
        data = fh.read()
    lines = data.split(b"\n")
    if size > TAIL:
        lines = lines[1:]
    for line in lines:
        try:
            yield json.loads(line)
        except ValueError:
            continue


def texts(content, wanted):
    if isinstance(content, str):
        return [content]
    return [b.get("text", "") for b in content or [] if isinstance(b, dict) and b.get("type") in wanted]


def is_prompt(kind, e):
    """A prompt someone typed or sent, not tool output, notices or injected instructions."""
    if kind == "claude":
        # ⚠️ Task notifications, command output, interrupts and compaction summaries arrive as
        # user entries too; only a real prompt starts a new turn.
        if e.get("type") != "user" or e.get("isMeta") or e.get("isCompactSummary"):
            return False
        candidates = texts((e.get("message") or {}).get("content"), {"text"})
    else:
        p = e.get("payload") or {}
        if e.get("type") != "response_item" or p.get("type") != "message" or p.get("role") != "user":
            return False
        candidates = texts(p.get("content"), {"input_text"})
    # ⚠️ Claude Code wraps pasted text (every brief) in <pasted_content>: that one tag is a prompt.
    return any(t.strip() and (t.lstrip().startswith("<pasted_content")
                              or not t.lstrip().startswith(("<", "[Request interrupted", "# AGENTS.md")))
               for t in candidates)


def reply_texts(kind, e):
    if kind == "claude":
        if e.get("type") != "assistant":
            return []
        return [t for t in texts((e.get("message") or {}).get("content"), {"text"}) if t.strip()]
    p = e.get("payload") or {}
    if e.get("type") == "response_item" and p.get("type") == "message" and p.get("role") == "assistant":
        return [t for t in texts(p.get("content"), {"output_text"}) if t.strip()]
    return []


def is_compaction(kind, e):
    if kind == "claude":
        return bool(e.get("isCompactSummary"))
    return e.get("type") == "compacted" or (e.get("payload") or {}).get("type") == "context_compacted"


def reply(kind, path):
    turn = []
    for e in entries(path):
        if is_prompt(kind, e):
            turn = []
        else:
            turn += [t.strip() for t in reply_texts(kind, e)]
    return "\n\n".join(turn) if turn else "(no reply since the last prompt)"


def news(kind, path, mark):
    size = os.path.getsize(path)
    try:
        start = int(open(mark).read())
    except (OSError, ValueError):
        start = size
    start = min(start, size)
    with open(path, "rb") as f:
        f.seek(start)
        chunk = f.read(size - start)
    end = chunk.rfind(b"\n") + 1
    with open(mark, "w") as f:
        f.write(str(start + end))
    event = ""
    for line in chunk[:end].splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if is_compaction(kind, e):
            event = "COMPACTED"
        elif not event and any(l.lstrip().startswith("CHECK-IN:")
                               for t in reply_texts(kind, e) for l in t.splitlines()):
            event = "CHECKIN"
    return event


def context(kind, path):
    n = 0
    for e in entries(path):
        if kind == "claude":
            u = (e.get("message") or {}).get("usage")
            if u:
                n = u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0) + u.get("cache_creation_input_tokens", 0)
        else:
            p = e.get("payload") or {}
            if p.get("type") == "token_count" and p.get("info"):
                n = (p["info"].get("last_token_usage") or {}).get("input_tokens", n)
    return n


def main(argv):
    if len(argv) < 3 or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if argv[:1] in (["-h"], ["--help"]) else 2
    cmd, kind, arg = argv[0], argv[1], argv[2]
    if cmd == "find":
        cwd = argv[argv.index("--cwd") + 1] if "--cwd" in argv else None
        since = float(argv[argv.index("--since") + 1]) if "--since" in argv else None
        print(find(kind, arg, cwd, since))
    elif cmd == "reply":
        print(reply(kind, arg))
    elif cmd == "prompts":
        print(sum(1 for e in entries(arg) if is_prompt(kind, e)))
    elif cmd == "news" and len(argv) == 4:
        print(news(kind, arg, argv[3]))
    elif cmd == "context":
        print(context(kind, arg))
    elif cmd == "size":
        print(os.path.getsize(arg))
    else:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
