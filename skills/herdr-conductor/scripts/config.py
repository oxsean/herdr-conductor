#!/usr/bin/env python3
"""Merged herdr-conductor configuration: built-in defaults < user file < project file.

  config.py show [--dir REPO]            the merged config, each value with where it came from
  config.py get KEY [--dir REPO]         one value, e.g. ledger.dir or pipeline.review
  config.py agent ROLE [--dir REPO]      the role's kind, then one agent argument per line
  config.py paths [--dir REPO]           the files read, in order

User file: $HERDR_CONDUCTOR_CONFIG, else ${XDG_CONFIG_HOME:-~/.config}/herdr-conductor/config.toml.
Project file: .herdr-conductor.toml at the top of REPO's git checkout.
"""
import os
import subprocess
import sys

try:
    import tomllib
except ModuleNotFoundError:
    try:
        import tomli as tomllib
    except ModuleNotFoundError:
        sys.exit("config.py: needs Python 3.11+ (tomllib) or the tomli package")

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULTS = os.path.join(os.path.dirname(HERE), "config.default.toml")
CHOICES = {
    "ledger.language": {"auto", "en", "zh"},
    "notify.method": {"push", "herdr", "none"},
    "pipeline.review": {"never", "checkin", "always"},
    "merge.strategy": {"ff", "squash", "rebase", "cherry-pick"},
    "merge.revalidate": {"always", "changed-tree"},
}
EFFORTS = {
    "claude": {"low", "medium", "high", "xhigh", "max"},
    "codex": {"minimal", "low", "medium", "high", "xhigh"},
}
# A project file comes with the repository, so it may pick agents but never add command-line
# arguments: those could turn off a worker's sandbox or approvals.
PROJECT_FORBIDDEN = {"args"}


def user_file():
    explicit = os.environ.get("HERDR_CONDUCTOR_CONFIG")
    if explicit:
        return os.path.expanduser(explicit)
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "herdr-conductor", "config.toml")


def project_file(repo):
    if not repo:
        return None
    try:
        top = subprocess.run(["git", "-C", repo, "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, check=True).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    return os.path.join(top, ".herdr-conductor.toml")


def load(path):
    with open(path, "rb") as f:
        return tomllib.load(f)


def merge(into, layer, source, origin, warnings, prefix=""):
    for key, value in layer.items():
        dotted = prefix + key
        if isinstance(value, dict):
            node = into.setdefault(key, {})
            if not isinstance(node, dict):
                warnings.append(f"{source}: {dotted} must be a table; ignored")
                continue
            merge(node, value, source, origin, warnings, dotted + ".")
        elif source.startswith("project") and key in PROJECT_FORBIDDEN:
            warnings.append(f"{source}: {dotted} is allowed only in the user file; ignored")
        else:
            into[key] = value
            origin[dotted] = source


def resolve(repo):
    config, origin, warnings, read = {}, {}, [], []
    layers = [("default", DEFAULTS), ("user", user_file()), ("project", project_file(repo))]
    for name, path in layers:
        if not path or not os.path.exists(path):
            continue
        try:
            data = load(path)
        except tomllib.TOMLDecodeError as e:
            sys.exit(f"config.py: {path}: {e}")
        read.append(f"{name}: {path}")
        merge(config, data, f"{name} ({path})" if name != "default" else "default", origin, warnings)
    for key, allowed in CHOICES.items():
        section, field = key.split(".")
        value = config.get(section, {}).get(field)
        if value is not None and value not in allowed:
            warnings.append(f"{key} = {value!r} is not one of {sorted(allowed)}")
    for role in config.get("pipeline", {}).get("coding_role", ""), config.get("pipeline", {}).get("review_role", ""):
        if role and role not in config.get("roles", {}):
            warnings.append(f"pipeline names role {role!r}, which is not defined under [roles]")
    acceptance = config.get("pipeline", {}).get("acceptance", "conductor")
    if acceptance != "conductor" and acceptance not in config.get("roles", {}):
        warnings.append(f"pipeline.acceptance = {acceptance!r} is neither 'conductor' nor a role")
    return config, origin, warnings, read


def agent_args(role, spec):
    kind = spec.get("kind") or "claude"
    model, effort = spec.get("model") or "", spec.get("effort") or ""
    if effort and kind in EFFORTS and effort not in EFFORTS[kind]:
        sys.exit(f"config.py: role {role}: effort {effort!r} is not valid for {kind} ({sorted(EFFORTS[kind])})")
    args = []
    if kind == "claude":
        args += ["--model", model] if model else []
        args += ["--effort", effort] if effort else []
    elif kind == "codex":
        args += ["-m", model] if model else []
        args += ["-c", f"model_reasoning_effort={effort}"] if effort else []
    elif model or effort:
        print(f"config.py: role {role}: kind {kind} takes no model/effort mapping; put them in args", file=sys.stderr)
    extra = spec.get("args", [])
    if not isinstance(extra, list) or not all(isinstance(a, str) for a in extra):
        sys.exit(f"config.py: role {role}: args must be a list of strings")
    return kind, args + extra


def main(argv):
    repo = None
    if "--dir" in argv:
        i = argv.index("--dir")
        repo = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0
    config, origin, warnings, read = resolve(repo)
    for w in warnings:
        print(f"config.py: warning: {w}", file=sys.stderr)
    cmd = argv[0]
    if cmd == "paths":
        print("\n".join(read))
    elif cmd == "get" and len(argv) == 2:
        node = config
        for part in argv[1].split("."):
            if not isinstance(node, dict) or part not in node:
                sys.exit(f"config.py: no key {argv[1]}")
            node = node[part]
        print(os.path.expanduser(node) if isinstance(node, str) and node.startswith("~") else node)
    elif cmd == "agent" and len(argv) == 2:
        roles = config.get("roles", {})
        if argv[1] not in roles:
            sys.exit(f"config.py: no role {argv[1]}; defined: {', '.join(sorted(roles))}")
        kind, args = agent_args(argv[1], roles[argv[1]])
        print(kind)
        print("\n".join(args))
    elif cmd == "show":
        def walk(node, prefix=""):
            for key, value in node.items():
                dotted = prefix + key
                if isinstance(value, dict):
                    walk(value, dotted + ".")
                else:
                    print(f"{dotted} = {value!r}    # {origin.get(dotted, '?')}")
        walk(config)
    else:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
