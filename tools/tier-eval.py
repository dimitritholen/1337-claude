#!/usr/bin/env python3
"""Offline eval harness for skills/tier/route.py's Jev question: scores
question-design variants against a fixture of known-tier steps, so a wording
change to the router can be judged before it goes live.

Input: --fixture (default tests/fixtures/tier-steps.jsonl), one JSON object
per line:

    {"id": 1, "task": "...", "title": "...", "brief": "...",
     "gold": "haiku"|"sonnet"|"opus", "why": "...", "tags": [...],
     "previous_attempt": {"tier": "sonnet", "outcome": "failed"}}  # optional

Rows are batched up to five at a time (route.py's own step limit) and sent
as one state/questions payload per batch, mirroring a real router call.

Variants (--variant, repeatable or comma-separated, default all):
  current   route.py's own CRITERIA and instructions, imported so the eval
            tracks the real router instead of a frozen copy: a Choice
            question with what/not_for/examples criteria per tier, plus
            previous_attempt in state -- this is the contrastive design a
            live eval run picked (accuracy 0.867, under-route 6.7%, identical
            over 2 runs, floor 0.6) over the plain-string criteria below.
  legacy    the router's old plain-string CRITERIA and instructions
            (accuracy 0.667), frozen here as the baseline current replaced.
  score     a Score question over three ordered situation levels;
            tier = round(score) via --score-cut.
  atomic    five per-step Noul questions, combined in code by a
            documented deterministic rule.

--dry-run prints one JSON line per batch (state + questions, tagged with
the variant) and needs no key or network. Otherwise a stored OpenRouter or
TypeSafe key is required (see lib/keys.py).

For variants current/legacy/score, route.py's own escalation rule
(confidence under --floor raises one tier, never above opus) is applied and
reported as a second, "escalated" column next to the raw prediction; atomic
has no single confidence to escalate on, so it reports only one column.

Output: a human table per variant to stdout (n, raw/escalated accuracy,
under-route rate -- predicting below gold, the costly error -- over-route
rate, a confusion matrix, and accuracy per confidence bucket). --json writes
the full per-row results to a file.

Exit codes match route.py: 2 bad input, 3 no key, 4 a Jev call failed.
"""

import argparse
import importlib.util
import json
import os
import sys
from collections import Counter

PLUGIN_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PLUGIN_ROOT)
from lib import jev, keys  # noqa: E402

# This eval measures Jev, never a forced tier: a user's own override left in
# the environment must not leak in here.
os.environ.pop("CLAUDE_1337_TIER_MODEL", None)
os.environ.pop("CLAUDE_PLUGIN_OPTION_TIER_MODEL", None)

# route.py lives under skills/tier/ with no __init__.py, so it is loaded by
# path rather than imported as a package -- this is the "import, don't copy"
# route the brief asks for, without turning skills/tier into a package.
_route_spec = importlib.util.spec_from_file_location(
    "tier_route", os.path.join(PLUGIN_ROOT, "skills", "tier", "route.py")
)
tier_route = importlib.util.module_from_spec(_route_spec)
_route_spec.loader.exec_module(tier_route)

TIERS = tier_route.TIERS  # ["haiku", "sonnet", "opus"]
VARIANTS = ["current", "legacy", "score", "atomic"]
DEFAULT_FIXTURE = os.path.join(PLUGIN_ROOT, "tests", "fixtures", "tier-steps.jsonl")
CONF_BUCKETS = [(0.0, 0.25), (0.25, 0.5), (0.5, 0.75), (0.75, 1.0)]


def fail(code, message):
    print(f"tier-eval: {message}", file=sys.stderr)
    sys.exit(code)


# --- fixture -----------------------------------------------------------

def read_fixture(path, limit=None):
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except OSError as e:
        fail(2, f"can't read fixture {path}: {e}")
    rows = []
    for lineno, raw in enumerate(lines, 1):
        raw = raw.strip()
        if not raw:
            continue
        try:
            row = json.loads(raw)
        except ValueError as e:
            fail(2, f"{path}:{lineno}: not JSON: {e}")
        if not isinstance(row, dict) or not row.get("task") or not row.get("title"):
            fail(2, f'{path}:{lineno}: needs "task" and "title"')
        if row.get("gold") not in TIERS:
            fail(2, f'{path}:{lineno}: "gold" must be one of {TIERS}, got {row.get("gold")!r}')
        rows.append(row)
    if not rows:
        fail(2, f"{path}: no rows")
    if limit:
        rows = rows[:limit]
    return rows


def batched(rows, size=5):
    for i in range(0, len(rows), size):
        yield rows[i:i + size]


def base_state(batch, with_previous=False):
    """(task, steps) shared by every variant: one task string (route.py's
    own shape) plus a step per row. Fixture rows are independent scenarios,
    so when a batch mixes different tasks the shared task names that
    explicitly instead of picking one row's task at random."""
    tasks = {row["task"] for row in batch}
    task = tasks.pop() if len(tasks) == 1 else (
        "Independent eval rows batched together for offline scoring; each "
        "step is its own unrelated task, ignore any relation between them."
    )
    steps = {}
    for i, row in enumerate(batch):
        step = {"title": row["title"], "brief": row.get("brief", "")}
        if with_previous and row.get("previous_attempt"):
            step["previous_attempt"] = row["previous_attempt"]
        steps[f"step_{i}"] = step
    return task, steps


# --- variant A: current ----------------------------------------------------

# route.py's live CRITERIA and instructions(), imported rather than copied
# (see module docstring), plus previous_attempt in state -- route.py builds
# its own state the same way (skills/tier/route.py's main()).
def build_current(batch):
    task, steps = base_state(batch, with_previous=True)
    state = {"task": task, "steps": steps}
    questions = {key: jev.choice(tier_route.instructions(key), tier_route.CRITERIA) for key in steps}
    return state, questions


def parse_choice_answer(answer):
    """Shared by current and legacy: both ask a plain Choice."""
    if not isinstance(answer, dict):
        return None, None, {}
    tier = answer.get("choice")
    if isinstance(tier, str):
        tier = tier.strip().lower()
    if tier not in TIERS:
        return None, None, {}
    confidence = answer.get("confidence")
    confidence = float(confidence) if confidence is not None else None
    probabilities = answer.get("probabilities") or {}
    return tier, confidence, probabilities


# --- variant B: legacy ------------------------------------------------------

# route.py's CRITERIA and instructions before the contrastive rewrite
# (accuracy 0.667 in the eval that picked "current" over this), frozen here
# as the baseline: git show HEAD:skills/tier/route.py:44-57,145-147.
LEGACY_CRITERIA = {
    "haiku": (
        "Mechanical: renames, moves, config edits, CRUD along an existing "
        "pattern, boilerplate, lookups, running checks."
    ),
    "sonnet": (
        "Pattern-following with judgment: a new endpoint or component "
        "matching existing conventions, straightforward tests, small refactors."
    ),
    "opus": (
        "Reasoning-heavy: new architecture, tricky algorithms, concurrency, "
        "security-sensitive paths, or a step that already failed at a lower tier."
    ),
}


def legacy_instructions(key):
    return (
        f"Which is the cheapest model tier that can build `steps.{key}` "
        "reliably in one go, as part of `task`? Cheap is the default; "
        "a higher tier must be earned by the hard part of the step."
    )


def build_legacy(batch):
    # The old router never had previous_attempt, so its state stays without
    # it -- the same "current does not build state with it" gap the
    # contrastive eval measured against.
    task, steps = base_state(batch)
    state = {"task": task, "steps": steps}
    questions = {key: jev.choice(legacy_instructions(key), LEGACY_CRITERIA) for key in steps}
    return state, questions


# --- variant C: score ------------------------------------------------------

# Ordered low -> high, each a situation judged in isolation (no "harder
# than the previous level"), no numbers -- per Jev's Score guidance.
SCORE_LEVELS = [
    "The step follows an existing pattern exactly and needs no new "
    "decisions: a rename, a config edit, boilerplate copied from a "
    "sibling, running an existing check.",
    "The step follows existing conventions but leaves a few choices open: "
    "a new endpoint or component shaped like its neighbours, a small "
    "refactor, tests for existing behaviour.",
    "The step has no existing pattern to follow, touches concurrency or a "
    "public API, schema or migration, is security-sensitive, or has "
    "already failed once at a lower tier.",
]


def build_score(batch):
    task, steps = base_state(batch, with_previous=True)
    state = {"task": task, "steps": steps}
    questions = {
        key: jev.score(
            f"How much judgment does `steps.{key}` need, as part of "
            f"`task`? When `steps.{key}.previous_attempt` is present, "
            "weigh its outcome.",
            SCORE_LEVELS,
        )
        for key in steps
    }
    return state, questions


def score_to_tier(score, cut):
    """round(score), but with the boundary offset configurable: cut=0.5 is
    an ordinary round-half-up at each level index."""
    idx = 0
    while idx < len(TIERS) - 1 and score >= idx + cut:
        idx += 1
    return TIERS[idx]


def parse_score_answer(answer, cut):
    if not isinstance(answer, dict):
        return None, None, {}
    raw_score = answer.get("score")
    if raw_score is None:
        return None, None, {}
    tier = score_to_tier(float(raw_score), cut)
    confidence = answer.get("confidence")
    confidence = float(confidence) if confidence is not None else None
    probabilities = answer.get("probabilities") or {}
    return tier, confidence, probabilities


# --- variant D: atomic ------------------------------------------------------

ATOMIC_NOULS = {
    "mechanical": "Is `steps.{key}` mechanical and fully specified: a "
                  "rename, move, config edit, CRUD copied from an existing "
                  "pattern, boilerplate, or running a check?",
    "concurrency": "Does `steps.{key}` touch concurrency, async "
                   "coordination or shared mutable state?",
    "public_api": "Does `steps.{key}` change a public API, a schema or a "
                  "migration?",
    "judgment": "Does `steps.{key}` need design judgment because its edge "
                "cases are unclear?",
    "failed_before": "Has `steps.{key}` already failed once at a lower "
                      "tier (see `steps.{key}.previous_attempt`)?",
}


def build_atomic(batch):
    task, steps = base_state(batch, with_previous=True)
    state = {"task": task, "steps": steps}
    questions = {}
    for key in steps:
        for name, template in ATOMIC_NOULS.items():
            questions[f"{key}__{name}"] = jev.noul(template.format(key=key))
    return state, questions


def noul_probability(answer):
    if not isinstance(answer, dict):
        return 0.0
    for field in ("probability", "noul"):
        value = answer.get(field)
        if value is not None:
            try:
                return float(value)
            except (TypeError, ValueError):
                continue
    return 0.0


def combine_atomic(probs):
    """Deterministic combine rule, documented here since there is no single
    Jev answer to defer to:
      1. failed_before >= 0.5 always earns opus -- a retry, matching
         CRITERIA's own "already failed at a lower tier".
      2. concurrency or public_api >= 0.5 earns opus -- hard-to-reason-about
         surfaces, even without open design judgment.
      3. judgment >= 0.5 and mechanical < 0.5 earns opus.
      4. mechanical >= 0.5 and none of concurrency/public_api/judgment hold
         earns haiku.
      5. otherwise sonnet -- partially mechanical, or open questions that
         are not judgment-heavy."""
    g = lambda name: probs.get(name, 0.0)  # noqa: E731
    if g("failed_before") >= 0.5:
        return "opus"
    if g("concurrency") >= 0.5 or g("public_api") >= 0.5:
        return "opus"
    if g("judgment") >= 0.5 and g("mechanical") < 0.5:
        return "opus"
    if g("mechanical") >= 0.5 and g("judgment") < 0.5 and g("concurrency") < 0.5 and g("public_api") < 0.5:
        return "haiku"
    return "sonnet"


# --- driver ----------------------------------------------------------------

def row_result(row, raw_tier, escalated_tier, confidence, probabilities, escalated=False):
    return {
        "id": row.get("id"),
        "task": row["task"],
        "title": row["title"],
        "gold": row["gold"],
        "raw_tier": raw_tier,
        "escalated_tier": escalated_tier,
        "escalated": escalated,
        "confidence": confidence,
        "probabilities": probabilities,
        "tags": row.get("tags"),
    }


def build_batch(name, batch):
    if name == "current":
        return build_current(batch)
    if name == "legacy":
        return build_legacy(batch)
    if name == "score":
        return build_score(batch)
    if name == "atomic":
        return build_atomic(batch)
    raise ValueError(name)


def evaluate_variant(name, rows, floor, score_cut, timeout, dry_run):
    results = []
    payloads = []
    for batch in batched(rows, 5):
        state, questions = build_batch(name, batch)
        payloads.append({"state": state, "questions": questions})
        if dry_run:
            continue
        try:
            response = jev.decide(state, questions, timeout=timeout)
        except jev.JevError as e:
            fail(4, f"Jev call failed ({name}): {e}")
        answers = response["answers"]

        if name == "atomic":
            for i, row in enumerate(batch):
                key = f"step_{i}"
                probs = {n: noul_probability(answers.get(f"{key}__{n}")) for n in ATOMIC_NOULS}
                tier = combine_atomic(probs)
                # No single Jev confidence exists for a Noul batch; this
                # ad-hoc "how decisive were the five answers" average is
                # only used for the confidence-bucket breakdown, and is
                # noted as such in the report.
                confidence = sum(max(p, 1 - p) for p in probs.values()) / len(probs)
                results.append(row_result(row, tier, tier, confidence, probs))
            continue

        for i, row in enumerate(batch):
            key = f"step_{i}"
            answer = answers.get(key)
            if name == "score":
                tier, confidence, probabilities = parse_score_answer(answer, score_cut)
            else:
                tier, confidence, probabilities = parse_choice_answer(answer)
            if tier is None:
                fail(4, f"Jev answered {key} ({name}) with an unusable answer: {answer!r}")
            escalated_tier, escalated = tier, False
            if confidence is not None and confidence < floor and tier != TIERS[-1]:
                escalated_tier = tier_route.escalate(tier)
                escalated = True
            results.append(row_result(row, tier, escalated_tier, confidence, probabilities, escalated))
    return results, payloads


def bucket_for(confidence):
    if confidence is None:
        return None
    idx = min(3, int(confidence // 0.25))
    lo, hi = CONF_BUCKETS[idx]
    return f"{lo:.2f}-{hi:.2f}"


def compute_metrics(results, use_escalated):
    n = len(results)
    correct = under = over = 0
    confusion = Counter()
    buckets = {}
    for r in results:
        pred = r["escalated_tier"] if use_escalated else r["raw_tier"]
        gold = r["gold"]
        confusion[(gold, pred)] += 1
        if pred == gold:
            correct += 1
        elif TIERS.index(pred) < TIERS.index(gold):
            under += 1
        else:
            over += 1
        bucket = bucket_for(r["confidence"])
        if bucket is not None:
            hit, total = buckets.get(bucket, (0, 0))
            buckets[bucket] = (hit + (pred == gold), total + 1)
    return {
        "n": n,
        "accuracy": correct / n if n else 0.0,
        "under_route_rate": under / n if n else 0.0,
        "over_route_rate": over / n if n else 0.0,
        "confusion": confusion,
        "bucket_accuracy": {b: (hit / total if total else 0.0) for b, (hit, total) in sorted(buckets.items())},
    }


def print_report(name, results):
    escalates = name != "atomic"
    raw = compute_metrics(results, use_escalated=False)
    print(f"=== {name} (n={raw['n']}) ===")
    print(f"  accuracy (raw){'      ' if escalates else ''}: {raw['accuracy']:.3f}")
    if escalates:
        esc = compute_metrics(results, use_escalated=True)
        print(f"  accuracy (escalated): {esc['accuracy']:.3f}")
    print(f"  under-route rate: {raw['under_route_rate']:.3f}  over-route rate: {raw['over_route_rate']:.3f}")
    print("  confusion (gold -> predicted, raw):")
    for gold in TIERS:
        row = " ".join(f"{pred}={raw['confusion'].get((gold, pred), 0)}" for pred in TIERS)
        print(f"    {gold:>7}: {row}")
    if raw["bucket_accuracy"]:
        print("  accuracy by confidence bucket (raw):")
        for bucket, acc in raw["bucket_accuracy"].items():
            print(f"    {bucket}: {acc:.3f}")


def parse_variants(values):
    if not values:
        return list(VARIANTS)
    names = []
    for item in values:
        names.extend(part.strip() for part in item.split(",") if part.strip())
    bad = [n for n in names if n not in VARIANTS]
    if bad:
        fail(2, f"unknown variant(s): {', '.join(bad)}; choose from {VARIANTS}")
    return names or list(VARIANTS)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--fixture", default=DEFAULT_FIXTURE)
    parser.add_argument("--variant", action="append", help="repeatable or comma-separated; default all")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--timeout", type=float, default=20.0)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--floor", type=float,
                         default=float(os.environ.get("CLAUDE_1337_TIER_FLOOR", str(tier_route.DEFAULT_FLOOR))))
    parser.add_argument("--score-cut", type=float, default=0.5)
    parser.add_argument("--json", dest="json_out")
    args = parser.parse_args(argv[1:])

    if not 0.0 <= args.floor <= 1.0:
        fail(2, f"--floor must be between 0 and 1, got {args.floor}")

    rows = read_fixture(args.fixture, args.limit)
    variants = parse_variants(args.variant)

    if not args.dry_run:
        try:
            jev.transport()
        except keys.MissingKey:
            fail(3, "no key: run /1337:visual setup once, or export "
                    "OPENROUTER_API_KEY (or TYPESAFE_API_KEY)")
        except keys.UnsafeFile as e:
            fail(3, str(e))

    all_results = {}
    all_payloads = {}
    for name in variants:
        results, payloads = evaluate_variant(name, rows, args.floor, args.score_cut, args.timeout, args.dry_run)
        all_results[name] = results
        all_payloads[name] = payloads

    if args.dry_run:
        for name in variants:
            for payload in all_payloads[name]:
                print(json.dumps({"variant": name, **payload}))
        return

    for name in variants:
        print_report(name, all_results[name])

    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as f:
            json.dump(all_results, f, indent=2)
        print(f"tier-eval: wrote {args.json_out}", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv)
