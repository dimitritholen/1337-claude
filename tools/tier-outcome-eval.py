#!/usr/bin/env python3
"""Outcome eval for tiered mode: replays real past changes with a builder on
each model tier and measures what comes out, so "is haiku good enough for
this step?" is answered by results rather than by router-vs-label agreement
(which is all tools/tier-eval.py measures).

Input: --fixture (default tests/fixtures/tier-outcome-steps.jsonl), one JSON
object per line:

    {"id": "o01", "commit": "<sha>", "parent": "<sha>",
     "difficulty": "trivial"|"ordinary"|"tricky", "brief": "...",
     "source_paths": ["..."], "hidden_tests": ["tests/x.test.sh"],
     "test_cmd": "bash tests/x.test.sh"}

Per row x tier (--tiers, default haiku,sonnet,opus), in a throwaway
`git worktree` of <parent> under a mkdtemp("1337-outcome-") dir:

  1. a builder run: `claude -p` with agents/builder.md's body, the brief and
     "work only here, run the tests", capped by --run-budget and
     --run-timeout;
  2. the diff against <parent>, untracked files included, taken before any
     test runs so files a test leaves behind stay out of it;
  3. `ripwire --quality-delta` (working tree vs HEAD, which is <parent>),
     also before the tests, so neither their leftovers nor the hidden tests
     count as the builder's change;
  4. the visible tests (test_cmd on the tree as the builder left it);
  5. the hidden tests: <commit>'s versions of hidden_tests checked out over
     the tree, test_cmd again; hidden_pass = exit 0 and no "FAIL " line;
  6. a blind review of brief + diff by --reviewer (no tier named), strict
     JSON scores 1-5 for correctness, design, maintainability.

One JSON line per row x tier is appended (and flushed) to --out, default
evals/results/tier-outcome/<UTC timestamp>.jsonl, then a report is printed.
`--report <raw.jsonl>` re-prints the report from a saved log.

Routing: skills/tier/route.py runs once up front as a subprocess, in batches
of at most five steps (its own limit), so the report can set each row's
routed tier against its "cheapest adequate tier": the cheapest tier whose
hidden tests pass and whose mean review score is within 0.5 of opus's (the
review condition is skipped when either score is missing). Exit 3/4 from
the router leaves the routed tier null; --no-route skips it.

Isolation of the child `claude` runs. The user's global install of this
plugin may have orchestrator or tiered mode on, whose hooks would refuse
the child's edits. hooks/lib/mode.sh reads three switches per mode; two are
env vars (CLAUDE_1337_*, EVAL_CLAUDE_1337_*) and are forced to 0 here, but
the third, CLAUDE_PLUGIN_OPTION_*, is set by Claude Code itself from the
plugin's userConfig when it runs a hook, so no env var of ours can clear it.
`claude --help` (2.1.281) offers `--safe-mode`: "Start with all
customizations (CLAUDE.md, skills, installed plugins, hooks, MCP servers,
custom commands and agents, ...) disabled ... Auth, model selection,
built-in tools and plugins, and permissions work normally." That is used
for every child. `--bare` would also skip plugin hooks but reads auth only
from ANTHROPIC_API_KEY, which breaks an OAuth login. Since safe mode drops
the project CLAUDE.md a real builder would see, the worktree's CLAUDE.md is
passed back in with --append-system-prompt. The parent session's own
CLAUDECODE / CLAUDE_CODE_* session variables are removed from the child env.

Permissions: `--permission-mode acceptEdits --allowedTools
Read,Edit,Write,Bash,Grep,Glob --permission-prompts none`, not
bypassPermissions: acceptEdits confines file edits to the working directory
(the worktree), the allowlist covers running tests, and anything else is
denied instead of waiting on a prompt. The reviewer runs with `--tools ""`.

--dry-run prints per row x tier the parent, the exact claude argv and env
overrides, and the router payload; its only subprocess is `git rev-parse
--verify` for the shas. It needs no key, network or `claude`.

Exit codes: 0 done, 2 bad args / missing fixture / bad sha, 3 no `claude`
on PATH (live mode only).
"""

import argparse
import concurrent.futures
import importlib.util
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from collections import defaultdict

PLUGIN_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROUTE_PY = os.path.join(PLUGIN_ROOT, "skills", "tier", "route.py")

# route.py has no package to import from; loaded by path, as tools/tier-eval.py does.
_route_spec = importlib.util.spec_from_file_location("tier_route", ROUTE_PY)
tier_route = importlib.util.module_from_spec(_route_spec)
_route_spec.loader.exec_module(tier_route)

TIERS = tier_route.TIERS
DIFFICULTIES = ["trivial", "ordinary", "tricky"]
DEFAULT_FIXTURE = os.path.join(PLUGIN_ROOT, "tests", "fixtures", "tier-outcome-steps.jsonl")
BUILDER_MD = os.path.join(PLUGIN_ROOT, "agents", "builder.md")
BUILDER_TOOLS = "Read,Edit,Write,Bash,Grep,Glob"
SCORE_KEYS = ["correctness", "design", "maintainability"]
FINAL_MESSAGE_CAP = 2048
QUALITY_TEXT_CAP = 4096
REVIEW_DIFF_CAP = 100_000
FAIL_LINES_CAP = 40
RAW_TEXT_CAP = 4096

# Env of the child `claude` runs and their tests: the parent session's own
# variables out, both env switches of every mode (hooks/lib/mode.sh) off.
SCRUB_NAMES = {
    "CLAUDECODE", "CLAUDE_PID", "CLAUDE_EFFORT", "CLAUDE_CODE_ENTRYPOINT",
    "CLAUDE_CODE_EXECPATH", "CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_CHILD_SESSION",
    "CLAUDE_CODE_SESSION_ATTENDED", "CLAUDE_CODE_MESSAGING_SOCKET",
    "CLAUDE_CODE_MESSAGING_TOKEN", "CLAUDE_CODE_BRIDGE_SESSION_ID",
}
SCRUB_PREFIXES = ("CLAUDE_PLUGIN_", "CLAUDE_1337_", "EVAL_CLAUDE_1337_")
MODE_OFF = {"CLAUDE_1337_ORCHESTRATOR": "0", "CLAUDE_1337_TIERED": "0",
            "EVAL_CLAUDE_1337_ORCHESTRATOR": "0", "EVAL_CLAUDE_1337_TIERED": "0"}

git_lock = threading.Lock()  # `git worktree add/remove` share .git/worktrees
live_worktrees = set()
stopping = threading.Event()  # set on Ctrl-C: workers start no further child
children = set()  # running child Popens, killed on Ctrl-C
children_lock = threading.Lock()


class Interrupted(Exception):
    pass


def note(message):
    print(f"tier-outcome-eval: {message}", file=sys.stderr)


def fail(code, message):
    note(message)
    sys.exit(code)


# --- input -------------------------------------------------------------

def read_fixture(path):
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except OSError as e:
        fail(2, f"can't read fixture {path}: {e}")
    rows = []
    for lineno, raw in enumerate(lines, 1):
        if not raw.strip():
            continue
        try:
            row = json.loads(raw)
        except ValueError as e:
            fail(2, f"{path}:{lineno}: not JSON: {e}")
        if not isinstance(row, dict):
            fail(2, f"{path}:{lineno}: not an object")
        for key in ("id", "commit", "parent", "brief", "test_cmd"):
            if not isinstance(row.get(key), str) or not row[key].strip():
                fail(2, f'{path}:{lineno}: needs a non-empty "{key}" string')
        if row.get("difficulty") not in DIFFICULTIES:
            fail(2, f'{path}:{lineno}: "difficulty" must be one of {DIFFICULTIES}')
        hidden = row.get("hidden_tests")
        if not isinstance(hidden, list) or not hidden or not all(isinstance(h, str) for h in hidden):
            fail(2, f'{path}:{lineno}: "hidden_tests" must be a non-empty list of paths')
        rows.append(row)
    if not rows:
        fail(2, f"{path}: no rows")
    ids = [r["id"] for r in rows]
    if len(set(ids)) != len(ids):
        fail(2, f"{path}: duplicate ids")
    return rows


def verify_shas(rows):
    for row in rows:
        for key in ("parent", "commit"):
            done = subprocess.run(
                ["git", "-C", PLUGIN_ROOT, "rev-parse", "--verify", "--quiet", row[key] + "^{commit}"],
                capture_output=True, text=True)
            if done.returncode != 0:
                fail(2, f"{row['id']}: {key} {row[key]!r} is not a commit in {PLUGIN_ROOT}")


def builder_role():
    text = open(BUILDER_MD, encoding="utf-8").read()
    match = re.match(r"^---\n.*?\n---\n", text, re.S)
    return (text[match.end():] if match else text).strip()


def builder_prompt(row):
    return (f"{builder_role()}\n\n# Brief\n\n{row['brief'].strip()}\n\n"
            "Work only inside this directory. Run the existing tests before you finish.")


def child_env():
    env = {k: v for k, v in os.environ.items()
           if k not in SCRUB_NAMES and not k.startswith(SCRUB_PREFIXES)}
    env.update(MODE_OFF)
    return env


def env_overrides():
    unset = sorted(k for k in os.environ
                   if (k in SCRUB_NAMES or k.startswith(SCRUB_PREFIXES)) and k not in MODE_OFF)
    return {"unset": unset, "set": MODE_OFF}


def builder_argv(prompt, tier, budget, claude_md):
    argv = ["claude", "-p", prompt, "--model", tier, "--output-format", "json",
            "--max-budget-usd", str(budget), "--permission-mode", "acceptEdits",
            "--allowedTools", BUILDER_TOOLS, "--permission-prompts", "none",
            "--safe-mode", "--no-session-persistence"]
    if claude_md:
        argv += ["--append-system-prompt", claude_md]
    return argv


def reviewer_argv(model, budget):
    # The prompt goes on stdin: brief plus diff can outgrow one argv string.
    return ["claude", "-p", "--model", model, "--output-format", "json",
            "--max-budget-usd", str(budget), "--tools", "", "--permission-prompts", "none",
            "--safe-mode", "--no-session-persistence"]


# --- subprocess helpers ------------------------------------------------

def kill_group(proc):
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except OSError:
        pass


def run(cmd, cwd, timeout, env=None, stdin=None, shell=False):
    """(exit code or None on timeout, stdout, stderr); never raises for the child.

    Each child gets its own process group, so a timeout or Ctrl-C kills the
    whole tree (a builder's test run, a test's own children), not just the
    direct child whose grandchildren would keep the pipes open.
    """
    if stopping.is_set():
        raise Interrupted()
    try:
        proc = subprocess.Popen(cmd, cwd=cwd, env=env, shell=shell, text=True, errors="replace",
                                stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                start_new_session=True)
    except OSError as e:
        return None, "", str(e)
    with children_lock:
        children.add(proc)
    try:
        out, err = proc.communicate(stdin, timeout=timeout)
        return proc.returncode, out, err
    except subprocess.TimeoutExpired:
        kill_group(proc)
        out, _ = proc.communicate()
        return None, out or "", "timeout"
    finally:
        with children_lock:
            children.discard(proc)


def git(*args, cwd=PLUGIN_ROOT):
    return run(["git", "-C", cwd, *args], None, 120)


def add_worktree(path, rev):
    with git_lock:
        code, _, err = git("worktree", "add", "--detach", path, rev)
        if code == 0:
            live_worktrees.add(path)
    if code != 0:
        raise RuntimeError(f"git worktree add failed: {err.strip()}")


def remove_worktree(path):
    # Straight subprocess, not run(): cleanup must still work after Ctrl-C.
    with git_lock:
        subprocess.run(["git", "-C", PLUGIN_ROOT, "worktree", "remove", "--force", path],
                       capture_output=True)
        live_worktrees.discard(path)
    shutil.rmtree(path, ignore_errors=True)


# --- parsing -----------------------------------------------------------

def parse_claude_json(stdout):
    """The `result` object of `claude -p --output-format json`; {} when absent."""
    try:
        data = json.loads(stdout)
    except (ValueError, TypeError):
        return {}
    if isinstance(data, list):
        results = [m for m in data if isinstance(m, dict) and m.get("type") == "result"]
        data = results[-1] if results else {}
    return data if isinstance(data, dict) else {}


def usage_fields(result, prefix):
    usage = result.get("usage") if isinstance(result.get("usage"), dict) else {}

    def num(value):
        return value if isinstance(value, (int, float)) and not isinstance(value, bool) else None

    return {
        f"{prefix}_cost_usd": num(result.get("total_cost_usd")),
        f"{prefix}_input_tokens": num(usage.get("input_tokens")),
        f"{prefix}_output_tokens": num(usage.get("output_tokens")),
        f"{prefix}_cache_creation_tokens": num(usage.get("cache_creation_input_tokens")),
        f"{prefix}_cache_read_tokens": num(usage.get("cache_read_input_tokens")),
        f"{prefix}_turns": num(result.get("num_turns")),
        f"{prefix}_is_error": result.get("is_error") if isinstance(result.get("is_error"), bool) else None,
    }


def count_lines(text):
    lines = text.splitlines()
    fails = [l for l in lines if l.startswith("FAIL ")]
    return (sum(1 for l in lines if l.startswith("ok ")), len(fails),
            [l[:RAW_TEXT_CAP] for l in fails[:FAIL_LINES_CAP]])


def _valid_scores(data):
    if not isinstance(data, dict):
        return None
    scores = {k: data.get(k) for k in SCORE_KEYS}
    if not all(isinstance(v, int) and not isinstance(v, bool) and 1 <= v <= 5 for v in scores.values()):
        return None
    notes = data.get("notes")
    scores["notes"] = notes if isinstance(notes, str) else ""
    return scores


def parse_scores(text):
    """{correctness, design, maintainability, notes} from a reply, or None.

    A `}` inside notes breaks a non-greedy regex match, so the whole text is
    tried first (after stripping code fences), then the substring from the
    first `{` to the last `}`.
    """
    if not isinstance(text, str):
        return None
    stripped = text.strip()
    stripped = re.sub(r"^```(?:json)?\s*|\s*```$", "", stripped, flags=re.S)
    try:
        scores = _valid_scores(json.loads(stripped))
        if scores:
            return scores
    except ValueError:
        pass
    start, end = stripped.find("{"), stripped.rfind("}")
    if start != -1 and end != -1 and end > start:
        try:
            return _valid_scores(json.loads(stripped[start:end + 1]))
        except ValueError:
            pass
    return None


def parse_quality(stdout):
    try:
        data = json.loads(stdout)
        return data.get("regressions") if isinstance(data.get("regressions"), int) else None
    except (ValueError, AttributeError):
        return None


# --- one row x tier ----------------------------------------------------

def run_tests(row, wt, env, timeout):
    code, out, err = run(row["test_cmd"], wt, timeout, env=env, shell=True)
    ok, failed, fail_lines = count_lines(out + "\n" + err)
    return code, ok, failed, fail_lines


def worktree_diff(row, wt):
    # A builder that committed anyway still gets judged on its whole change:
    # HEAD back to <parent>, changes kept, so the diff and ripwire's
    # working-tree-vs-HEAD delta both see all of it.
    code, head, _ = git("rev-parse", "HEAD", cwd=wt)
    _, parent, _ = git("rev-parse", row["parent"], cwd=wt)
    if code == 0 and head.strip() != parent.strip():
        git("reset", "--soft", row["parent"], cwd=wt)
    git("add", "-N", "--", ".", cwd=wt)  # untracked files into the diff
    _, diff, _ = git("diff", row["parent"], cwd=wt)
    return diff


def quality_delta(wt):
    if not shutil.which("ripwire"):
        return {"quality_exit": None, "quality_regressions": None, "quality_raw": None}
    code, out, err = run(["ripwire", ".", "--quality-delta", "--json"], wt, 300)
    regressions = parse_quality(out)
    return {"quality_exit": code, "quality_regressions": regressions,
            "quality_raw": None if regressions is not None else (out + err)[:QUALITY_TEXT_CAP]}


def review_prompt(row, diff, retry):
    if len(diff) > REVIEW_DIFF_CAP:
        diff = diff[:REVIEW_DIFF_CAP] + "\n[diff truncated]\n"
    ask = ("Review this change against its brief. Judge only the change. Reply with "
           'strict JSON and nothing else: {"correctness": 1-5, "design": 1-5, '
           '"maintainability": 1-5, "notes": "<two sentences at most>"}. '
           "5 is best; an empty diff scores 1 on correctness.")
    if retry:
        ask += " Your last reply was not parseable: reply with the JSON object only."
    return f"{ask}\n\n# Brief\n\n{row['brief'].strip()}\n\n# Diff\n\n```diff\n{diff}```\n"


def blind_review(row, diff, args, env):
    record = {"review": None, "review_attempts": [], **usage_fields({}, "reviewer")}
    tokens = defaultdict(int)
    review_dir = tempfile.mkdtemp(prefix="1337-outcome-review-")
    try:
        for retry in (False, True):
            code, out, err = run(reviewer_argv(args.reviewer, args.review_budget), review_dir,
                                 args.run_timeout, env=env, stdin=review_prompt(row, diff, retry))
            result = parse_claude_json(out)
            fields = usage_fields(result, "reviewer")
            record["review_attempts"].append({
                "exit": code, "is_error": fields.get("reviewer_is_error"),
                "subtype": result.get("subtype") if isinstance(result.get("subtype"), str) else None,
                "cost_usd": fields.get("reviewer_cost_usd"), "num_turns": fields.get("reviewer_turns"),
                "stdout": (out or "")[:RAW_TEXT_CAP], "stderr": (err or "")[:RAW_TEXT_CAP],
            })
            for key, value in fields.items():  # both attempts count toward spend
                if value is not None and key != "reviewer_is_error":
                    tokens[key] += value
            record.update(fields)
            record.update(tokens)
            scores = parse_scores(result.get("result"))
            if scores:
                record["review"] = scores
                break
    finally:
        shutil.rmtree(review_dir, ignore_errors=True)
    return record


def run_one(row, tier, routed, args, tmp, env):
    wt = os.path.join(tmp, f"{row['id']}-{tier}")
    record = {"id": row["id"], "tier": tier, "difficulty": row["difficulty"], "routed": routed,
              "commit": row["commit"], "parent": row["parent"], "error": None}
    try:
        add_worktree(wt, row["parent"])
        md_path = os.path.join(wt, "CLAUDE.md")
        claude_md = open(md_path, encoding="utf-8").read() if os.path.isfile(md_path) else None
        started = time.monotonic()
        code, out, err = run(builder_argv(builder_prompt(row), tier, args.run_budget, claude_md),
                             wt, args.run_timeout, env=env)
        result = parse_claude_json(out)
        final = result.get("result") if isinstance(result.get("result"), str) else (out or err)
        record.update({"builder_exit": code, "builder_timeout": code is None and err == "timeout",
                       "builder_seconds": round(time.monotonic() - started, 1),
                       **usage_fields(result, "builder"),
                       "builder_final": (final or "")[:FINAL_MESSAGE_CAP]})

        # The builder's change, snapshotted before any test can leave files
        # behind and before the hidden tests land in the tree.
        diff = worktree_diff(row, wt)
        record["diff_lines"] = sum(1 for l in diff.splitlines()
                                   if l[:1] in "+-" and not l.startswith(("+++", "---")))
        record.update(quality_delta(wt))

        code, ok, failed, fail_lines = run_tests(row, wt, env, args.run_timeout)
        record.update({"visible_exit": code, "visible_ok": ok, "visible_fail": failed,
                       "visible_pass": code == 0 and failed == 0, "visible_fail_lines": fail_lines})

        code, _, err = git("checkout", row["commit"], "--", *row["hidden_tests"], cwd=wt)
        if code != 0:
            record.update({"hidden_exit": None, "hidden_ok": None, "hidden_fail": None,
                           "hidden_pass": None, "hidden_fail_lines": [],
                           "error": f"hidden checkout: {err.strip()}"})
        else:
            code, ok, failed, fail_lines = run_tests(row, wt, env, args.run_timeout)
            record.update({"hidden_exit": code, "hidden_ok": ok, "hidden_fail": failed,
                           "hidden_pass": code == 0 and failed == 0, "hidden_fail_lines": fail_lines})

        if not args.no_review:
            record.update(blind_review(row, diff, args, env))
    except Interrupted:
        record["error"] = "interrupted"
    except Exception as e:  # one broken row x tier must not sink the rest
        record["error"] = f"{type(e).__name__}: {e}"
    finally:
        if os.path.exists(wt) or wt in live_worktrees:
            remove_worktree(wt)
    return record


# --- routing -----------------------------------------------------------

def route_payloads(rows):
    for i in range(0, len(rows), 5):
        batch = rows[i:i + 5]
        yield batch, {"task": "Outcome eval replay",
                      "steps": [{"id": n, "title": r["id"], "brief": r["brief"]}
                                for n, r in enumerate(batch, 1)]}


def route(rows):
    routed = {}
    for batch, payload in route_payloads(rows):
        code, out, err = run([sys.executable, ROUTE_PY], PLUGIN_ROOT, 120, stdin=json.dumps(payload))
        if code != 0:
            note(f"route.py exit {code}: {err.strip().splitlines()[0] if err.strip() else ''}; "
                 "routed tier null for this batch")
            continue
        try:
            steps = json.loads(out.splitlines()[0])["steps"]
        except (ValueError, KeyError, IndexError, TypeError):
            note("route.py output unreadable; routed tier null for this batch")
            continue
        by_id = {s.get("id"): s.get("tier") for s in steps if isinstance(s, dict)}
        for n, row in enumerate(batch, 1):
            routed[row["id"]] = by_id.get(n) if by_id.get(n) in TIERS else None
    return routed


# --- report ------------------------------------------------------------

def numbers(values):
    return [v for v in values if isinstance(v, (int, float)) and not isinstance(v, bool)]


def mean(values):
    values = numbers(values)
    return sum(values) / len(values) if values else None


def rate(values):
    values = [v for v in values if isinstance(v, bool)]
    return sum(values) / len(values) if values else None


def fmt(value, digits=2):
    return "-" if value is None else f"{value:.{digits}f}"


def rate_of(values):
    """`rate/N`, N the runs with a known pass/fail."""
    return f"{fmt(rate(values))}/{sum(1 for v in values if isinstance(v, bool))}"


def mean_of(values, digits=2):
    """`mean/N`, N the runs with a known value; unknown is never counted as 0."""
    return f"{fmt(mean(values), digits)}/{len(numbers(values))}"


def failed_run(record):
    return bool(record.get("error") or record.get("builder_timeout") or record.get("builder_is_error"))


def review_mean(record):
    review = record.get("review")
    return mean([review.get(k) for k in SCORE_KEYS]) if isinstance(review, dict) else None


def cheapest_adequate(by_tier):
    opus_score = review_mean(by_tier["opus"]) if "opus" in by_tier else None
    for tier in TIERS:
        record = by_tier.get(tier)
        if not record or record.get("hidden_pass") is not True:
            continue
        score = review_mean(record)
        if opus_score is None or score is None or score >= opus_score - 0.5:
            return tier
    return None


def report(records):
    tiers = [t for t in TIERS if any(r.get("tier") == t for r in records)]
    print("== per tier: outcome (runs = all runs; x/N = value over the N runs where it is known)")
    print(f"{'tier':8} {'runs':>4} {'err/timeout':>11} {'visible':>9} {'hidden':>9} "
          f"{'corr':>8} {'design':>8} {'maint':>8}")
    for tier in tiers:
        rs = [r for r in records if r.get("tier") == tier]
        reviews = [r["review"] for r in rs if isinstance(r.get("review"), dict)]
        print(f"{tier:8} {len(rs):>4} {sum(map(failed_run, rs)):>11} "
              f"{rate_of([r.get('visible_pass') for r in rs]):>9} "
              f"{rate_of([r.get('hidden_pass') for r in rs]):>9} "
              + " ".join(f"{mean_of([v.get(k) for v in reviews]):>8}" for k in SCORE_KEYS))

    print("\n== per tier: spend (unknown $ = no cost reported, e.g. a killed run; "
          "means and totals are over the N known)")
    print(f"{'tier':8} {'runs':>4} {'unknown $':>9} {'builder mean $':>14} {'builder $':>9} "
          f"{'reviewer mean $':>15} {'reviewer $':>10} {'in tok':>9} {'out tok':>8} "
          f"{'cache c':>9} {'cache r':>10}")
    for tier in tiers:
        rs = [r for r in records if r.get("tier") == tier]
        builder = [r.get("builder_cost_usd") for r in rs]
        reviewer = [r.get("reviewer_cost_usd") for r in rs]

        def tok(key):
            return sum(numbers(r.get(key) for r in rs))

        print(f"{tier:8} {len(rs):>4} {len(rs) - len(numbers(builder)):>9} "
              f"{mean_of(builder, 3):>14} {sum(numbers(builder)):>9.3f} "
              f"{mean_of(reviewer, 3):>15} {sum(numbers(reviewer)):>10.3f} "
              f"{tok('builder_input_tokens'):>9} {tok('builder_output_tokens'):>8} "
              f"{tok('builder_cache_creation_tokens'):>9} {tok('builder_cache_read_tokens'):>10}")
    builder = [r.get("builder_cost_usd") for r in records]
    reviewer = [r.get("reviewer_cost_usd") for r in records]
    print(f"total $: builder {sum(numbers(builder)):.3f} ({len(numbers(builder))} of {len(records)} "
          f"runs known) + reviewer {sum(numbers(reviewer)):.3f} ({len(numbers(reviewer))} known) = "
          f"{sum(numbers(builder)) + sum(numbers(reviewer)):.3f}")

    print("\n== hidden pass rate/N, difficulty x tier (N = runs with a known hidden result)")
    print(f"{'difficulty':10} " + " ".join(f"{t:>9}" for t in tiers))
    for difficulty in DIFFICULTIES:
        rs = [r for r in records if r.get("difficulty") == difficulty]
        if rs:
            print(f"{difficulty:10} " + " ".join(
                f"{rate_of([r.get('hidden_pass') for r in rs if r.get('tier') == t]):>9}" for t in tiers))

    print("\n== routing")
    by_row = defaultdict(dict)
    for r in records:
        by_row[r["id"]][r.get("tier")] = r  # a later duplicate wins
    counts = defaultdict(int)
    routed_cost = opus_cost = 0.0
    priced = 0
    print(f"{'id':10} {'routed':>7} {'adequate':>9}  verdict")
    for row_id, by_tier in by_row.items():
        routed = next((r.get("routed") for r in by_tier.values() if r.get("routed")), None)
        adequate = cheapest_adequate(by_tier)
        if routed is None:
            verdict = "unrouted"
        elif adequate is None:
            verdict = "no adequate tier"
        elif TIERS.index(routed) < TIERS.index(adequate):
            verdict = "under-routed"
        elif TIERS.index(routed) > TIERS.index(adequate):
            verdict = "over-routed"
        else:
            verdict = "matched"
        counts[verdict] += 1
        print(f"{row_id:10} {routed or '-':>7} {adequate or '-':>9}  {verdict}")
        cost_routed = (by_tier.get(routed) or {}).get("builder_cost_usd") if routed else None
        cost_opus = (by_tier.get("opus") or {}).get("builder_cost_usd")
        if isinstance(cost_routed, (int, float)) and isinstance(cost_opus, (int, float)):
            routed_cost += cost_routed
            opus_cost += cost_opus
            priced += 1
    print("counts: " + ", ".join(f"{k} {counts[k]}" for k in
                                 ("matched", "under-routed", "over-routed", "no adequate tier", "unrouted")))
    if priced:
        print(f"builder $, routed plan vs all-opus over {priced} priced rows: "
              f"{routed_cost:.3f} vs {opus_cost:.3f}")
    else:
        print("builder $, routed plan vs all-opus: no row has both prices")


def read_log(path):
    records = []
    try:
        for line in open(path, encoding="utf-8"):
            if line.strip():
                try:
                    records.append(json.loads(line))
                except ValueError:
                    note(f"{path}: skipping an unreadable line")
    except OSError as e:
        fail(2, f"can't read {path}: {e}")
    return [r for r in records if isinstance(r, dict) and "id" in r]


# --- main --------------------------------------------------------------

def parse_args(argv):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--fixture", default=DEFAULT_FIXTURE)
    p.add_argument("--tiers", default=",".join(TIERS))
    p.add_argument("--limit", type=int)
    p.add_argument("--only", help="comma-separated row ids")
    p.add_argument("--jobs", type=int, default=1)
    p.add_argument("--run-budget", type=float, default=2.0, help="USD cap per builder claude run")
    p.add_argument("--review-budget", type=float, default=0.25, help="USD cap per reviewer claude run")
    p.add_argument("--run-timeout", type=float, default=900, help="seconds per claude run or test run")
    p.add_argument("--reviewer", default="opus")
    p.add_argument("--out")
    p.add_argument("--report", metavar="RAW_JSONL", help="re-print the report from a saved log")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--no-review", action="store_true")
    p.add_argument("--no-route", action="store_true")
    args = p.parse_args(argv)
    args.tiers = [t.strip() for t in args.tiers.split(",") if t.strip()]
    if not args.tiers or any(t not in TIERS for t in args.tiers):
        p.error(f"--tiers takes a comma-separated subset of {TIERS}")
    if args.jobs < 1 or (args.limit is not None and args.limit < 1):
        p.error("--jobs and --limit must be at least 1")
    if args.run_budget <= 0 or args.review_budget <= 0 or args.run_timeout <= 0:
        p.error("--run-budget, --review-budget and --run-timeout must be positive")
    return args


def select_rows(args):
    rows = read_fixture(args.fixture)
    if args.only:
        wanted = [i.strip() for i in args.only.split(",") if i.strip()]
        missing = set(wanted) - {r["id"] for r in rows}
        if missing:
            fail(2, f"--only names unknown ids: {', '.join(sorted(missing))}")
        rows = [r for r in rows if r["id"] in wanted]
    return rows[:args.limit] if args.limit else rows


def dry_run(rows, args):
    tmp = os.path.join(tempfile.gettempdir(), "1337-outcome-<random>")
    overrides = env_overrides()
    for row in rows:
        for tier in args.tiers:
            wt = os.path.join(tmp, f"{row['id']}-{tier}")
            print(json.dumps({
                "id": row["id"], "tier": tier, "parent": row["parent"], "commit": row["commit"],
                "worktree": wt,
                "builder_argv": builder_argv(builder_prompt(row), tier, args.run_budget,
                                             f"<contents of {wt}/CLAUDE.md, when present>"),
                "reviewer_argv": None if args.no_review else reviewer_argv(args.reviewer, args.review_budget),
                "env": overrides,
            }))
    if not args.no_route:
        for _, payload in route_payloads(rows):
            print(json.dumps({"router_payload": payload}))


def main(argv):
    args = parse_args(argv)
    if args.report:
        report(read_log(args.report))
        return 0
    rows = select_rows(args)
    verify_shas(rows)
    if args.dry_run:
        dry_run(rows, args)
        return 0
    if not shutil.which("claude"):
        fail(3, "no `claude` on PATH")

    routed = {} if args.no_route else route(rows)
    out = args.out or os.path.join(PLUGIN_ROOT, "evals", "results", "tier-outcome",
                                   time.strftime("%Y-%m-%dT%H-%M-%SZ", time.gmtime()) + ".jsonl")
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    env = child_env()
    tmp = tempfile.mkdtemp(prefix="1337-outcome-")
    records = []
    pool = concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs)
    try:
        with open(out, "a", encoding="utf-8") as log:
            futures = [pool.submit(run_one, row, tier, routed.get(row["id"]), args, tmp, env)
                       for row in rows for tier in args.tiers]
            for future in concurrent.futures.as_completed(futures):
                record = future.result()
                records.append(record)
                log.write(json.dumps(record) + "\n")
                log.flush()
                note(f"{record['id']} {record['tier']}: hidden_pass={record.get('hidden_pass')}"
                     + (f" error={record['error']}" if record.get("error") else ""))
    except KeyboardInterrupt:
        note("interrupted; cleaning up worktrees")
        stopping.set()
        with children_lock:
            for proc in list(children):
                kill_group(proc)
        raise
    finally:
        pool.shutdown(wait=True, cancel_futures=True)
        for wt in list(live_worktrees):
            remove_worktree(wt)
        subprocess.run(["git", "-C", PLUGIN_ROOT, "worktree", "prune"], capture_output=True)
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"raw log: {out}\n")
    report(records)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
