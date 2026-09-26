#!/usr/bin/env bash
# Drift check for shared rule text: hooks, skills and styles repeat sentences
# that must stay aligned, because styles and hook payloads cannot include each
# other. A FAIL means a rule was edited in one copy but not the others.
set -u

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
fail=0

need() { # file string description
  grep -qF -- "$2" "$ROOT/$1" || { printf 'FAIL %s: missing "%s"\n' "$1" "$3"; fail=1; }
}

# Every style file carries the shared scaffolding.
for style in l33t unc tremendous silent hippy pimp surfer yoda; do
  f="output-styles/$style.md"
  need "$f" "keep-coding-instructions: true" "frontmatter"
  need "$f" "Changes how Claude talks, never what it does." "contract line"
  need "$f" "## Where the voice lives" "voice-lives section"
  need "$f" "## Say as little as needed" "brevity section"
  need "$f" "Use the fewest words that are complete and correct." "brevity core"
  need "$f" "## Quality is untouchable" "quality section"
done

# The persona-in-tissue rule: all voices except silent, which has no persona.
for style in l33t unc tremendous hippy pimp surfer yoda; do
  need "output-styles/$style.md" \
    "The persona lives in the connective tissue, never in new sentences." "persona rule"
done

# The build ladder and its reading rule: hooks and the skills that judge code.
for f in hooks/evaluate.md hooks/subagent.md skills/review/SKILL.md skills/plan/SKILL.md; do
  need "$f" "Already in this codebase?" "ladder rung 1"
  need "$f" "Lazy about the solution, never about reading" "reading rule"
done

# The never-cut rule, identical wording in the two hook copies. The anchor
# must fit on one wrapped line in both files.
for f in hooks/evaluate.md hooks/subagent.md skills/plan/SKILL.md; do
  need "$f" \
    "data-loss guards, accessibility and tests are never cut" \
    "never-cut rule"
done

# The skills express the same never-cut rule in review voice.
for f in skills/review/SKILL.md skills/audit/SKILL.md; do
  need "$f" "never over-engineering" "never-cut rule"
done

# Drift check 1: Numbers in hooks/orchestrator.md equal the defaults in hooks.
# Extract the default value from lines like: VARIABLE="${CLAUDE_1337_VARIABLE:-DEFAULT}"
# and assert the same number appears next to the variable name in orchestrator.md.

# CLAUDE_1337_READ_CAP and CLAUDE_1337_GREP_CAP from read-cap.sh should be 0
hook_read_cap=$(grep 'CLAUDE_1337_READ_CAP:-' "$ROOT/hooks/read-cap.sh" | head -1 | sed -n 's/.*CLAUDE_1337_READ_CAP:-\([0-9]*\).*/\1/p')
if [ "$hook_read_cap" != "0" ]; then
  printf 'FAIL hooks/read-cap.sh: CLAUDE_1337_READ_CAP default is %s, expected 0\n' "$hook_read_cap" >&2
  fail=1
fi

hook_grep_cap=$(grep 'CLAUDE_1337_GREP_CAP:-' "$ROOT/hooks/read-cap.sh" | head -1 | sed -n 's/.*CLAUDE_1337_GREP_CAP:-\([0-9]*\).*/\1/p')
if [ "$hook_grep_cap" != "0" ]; then
  printf 'FAIL hooks/read-cap.sh: CLAUDE_1337_GREP_CAP default is %s, expected 0\n' "$hook_grep_cap" >&2
  fail=1
fi

# CLAUDE_1337_MAX_LINES from orchestrator-guard.sh should be 20
hook_max_lines=$(grep 'CLAUDE_1337_MAX_LINES:-' "$ROOT/hooks/orchestrator-guard.sh" | head -1 | sed -n 's/.*CLAUDE_1337_MAX_LINES:-\([0-9]*\).*/\1/p')
if [ "$hook_max_lines" != "20" ]; then
  printf 'FAIL hooks/orchestrator-guard.sh: CLAUDE_1337_MAX_LINES default is %s, expected 20\n' "$hook_max_lines" >&2
  fail=1
fi

# CLAUDE_1337_EDIT_CAP from orchestrator-guard.sh should be 3
hook_edit_cap=$(grep 'CLAUDE_1337_EDIT_CAP:-' "$ROOT/hooks/orchestrator-guard.sh" | head -1 | sed -n 's/.*CLAUDE_1337_EDIT_CAP:-\([0-9]*\).*/\1/p')
if [ "$hook_edit_cap" != "3" ]; then
  printf 'FAIL hooks/orchestrator-guard.sh: CLAUDE_1337_EDIT_CAP default is %s, expected 3\n' "$hook_edit_cap" >&2
  fail=1
fi

# Now check that orchestrator.md mentions these numbers (not necessarily with variable names)
# Line 16-17 mentions "0" for READ_CAP and GREP_CAP
if ! grep -q "default to 0" "$ROOT/hooks/orchestrator.md"; then
  printf 'FAIL hooks/orchestrator.md: does not mention "default to 0" for read/grep caps\n' >&2
  fail=1
fi

# Line 36 mentions CLAUDE_1337_MAX_LINES, and line 33 says "about 20 lines"
if ! grep -q "20 lines" "$ROOT/hooks/orchestrator.md"; then
  printf 'FAIL hooks/orchestrator.md: does not mention "20 lines" for max edit size\n' >&2
  fail=1
fi

# Line 48 mentions CLAUDE_1337_EDIT_CAP and "3"
if ! grep -q "refuses past 3" "$ROOT/hooks/orchestrator.md"; then
  printf 'FAIL hooks/orchestrator.md: does not mention "3" for edit cap\n' >&2
  fail=1
fi

[ "$fail" -eq 0 ] && printf 'ok   cap defaults match orchestrator.md\n'

# Drift check 2: hooks/tiered.md and skills/tier/SKILL.md have identical route.py invocation
# Compare the command (ignoring leading whitespace from markdown indentation)
tiered_route=$(grep 'python3 "${CLAUDE_PLUGIN_ROOT}/skills/tier/route.py" <<'"'"'EOF'"'"'' "$ROOT/hooks/tiered.md" | head -1 | sed 's/^[[:space:]]*//')
skill_route=$(grep 'python3 "${CLAUDE_PLUGIN_ROOT}/skills/tier/route.py" <<'"'"'EOF'"'"'' "$ROOT/skills/tier/SKILL.md" | head -1 | sed 's/^[[:space:]]*//')

if [ "$tiered_route" != "$skill_route" ]; then
  printf 'FAIL: route.py invocation line differs between hooks/tiered.md and skills/tier/SKILL.md\n' >&2
  fail=1
else
  printf 'ok   route.py invocation identical in tiered.md and tier/SKILL.md\n'
fi

# Drift check 3: Every keyword in Tiers section of SKILL.md appears in CRITERIA in route.py
# route.py's CRITERIA is the contrastive wording tools/tier-eval.py's live eval
# picked (see CRITERIA's own comment in route.py); these keyword lists are shared
# by SKILL.md's Tiers section and route.py's CRITERIA, so the two stay one rulebook.
# Keywords from Haiku: renames, moves, config edits, CRUD, existing pattern, boilerplate, running checks
# Keywords from Sonnet: new endpoint, new component, shaped like its neighbours, unit tests, small refactor
# Keywords from Opus: new architecture, tricky algorithms, concurrency, security-sensitive paths

for key in renames moves config CRUD boilerplate checks; do
  if ! grep -q "$key" "$ROOT/skills/tier/route.py"; then
    printf 'FAIL skills/tier/route.py CRITERIA: missing haiku keyword "%s"\n' "$key" >&2
    fail=1
  fi
done

for key in endpoint component neighbours tests refactor; do
  if ! grep -q "$key" "$ROOT/skills/tier/route.py"; then
    printf 'FAIL skills/tier/route.py CRITERIA: missing sonnet keyword "%s"\n' "$key" >&2
    fail=1
  fi
done

for key in architecture algorithms concurrency "security-sensitive"; do
  if ! grep -q "$key" "$ROOT/skills/tier/route.py"; then
    printf 'FAIL skills/tier/route.py CRITERIA: missing opus keyword "%s"\n' "$key" >&2
    fail=1
  fi
done

[ "$fail" -eq 0 ] && printf 'ok   tier keywords in SKILL.md match route.py CRITERIA\n'

# Drift check 4: Test list in docs (docs/testing.md) equals ls tests/*.test.sh basenames
# Extract the test list from docs/testing.md: lines with `tests/*.test.sh`
doc_tests=$(grep '`tests/.*\.test\.sh`' "$ROOT/docs/testing.md" | sed -E 's/.*`tests\/([^`]+)`/\1/' | sort)
actual_tests=$(ls "$ROOT/tests"/*.test.sh 2>/dev/null | xargs -I {} basename {} | sort)

# Check for missing from docs (in actual but not in docs)
for test in $actual_tests; do
  if ! echo "$doc_tests" | grep -qx "$test"; then
    printf 'FAIL docs/testing.md: missing test suite "%s"\n' "$test" >&2
    fail=1
  fi
done

# Check for extra in docs (in docs but not in actual)
for test in $doc_tests; do
  if ! echo "$actual_tests" | grep -qx "$test"; then
    printf 'FAIL docs/testing.md: extra test suite "%s" not found on disk\n' "$test" >&2
    fail=1
  fi
done

test_count=$(echo "$actual_tests" | wc -l)
[ "$fail" -eq 0 ] && printf 'ok   test suite list in docs/testing.md matches ls tests/*.test.sh (%d tests)\n' "$test_count"

# Drift check 5: Every tool in guard-corpus.jsonl matches a PreToolUse matcher in hooks.json
# Extract distinct tools from guard-corpus.jsonl
guard_tools=$(grep -o '"tool":"[^"]*"' "$ROOT/tests/fixtures/guard-corpus.jsonl" | cut -d'"' -f4 | sort -u)

# Extract matchers from hooks.json PreToolUse section
# Matchers: Edit|Write|MultiEdit|NotebookEdit|Bash
#           Read|Grep|Glob|Bash|WebFetch|mcp__codebase-memory-mcp__(get_code_snippet|search_code|search_graph)
#           Agent|Task
#           Bash|Agent|Task

for tool in $guard_tools; do
  if ! grep -q "\"matcher\".*\"[^\"]*$tool" "$ROOT/hooks/hooks.json"; then
    printf 'FAIL hooks/hooks.json: no PreToolUse matcher for tool "%s"\n' "$tool" >&2
    fail=1
  fi
done

# Also check MCP read tool names from read-cap.sh are in hooks.json matchers
if ! grep -q "codebase-memory-mcp" "$ROOT/hooks/hooks.json"; then
  printf 'FAIL hooks/hooks.json: mcp tools from read-cap.sh not covered in matchers\n' >&2
  fail=1
fi

[ "$fail" -eq 0 ] && printf 'ok   guard-corpus tools and MCP tools covered in hooks.json matchers\n'

# Drift check 6: plugin.json descriptions mention line limit and allowlist
plugin_orch_desc=$(grep -A 1 '"Orchestrator mode"' "$ROOT/.claude-plugin/plugin.json" | grep "description")

if ! echo "$plugin_orch_desc" | grep -q "20"; then
  printf 'FAIL .claude-plugin/plugin.json: orchestrator description missing line limit (20)\n' >&2
  fail=1
fi

if ! echo "$plugin_orch_desc" | grep -q "CLAUDE_1337_BASH_ALLOW"; then
  printf 'FAIL .claude-plugin/plugin.json: orchestrator description missing CLAUDE_1337_BASH_ALLOW mention\n' >&2
  fail=1
fi

[ "$fail" -eq 0 ] && printf 'ok   plugin.json descriptions mention line limit and allowlist\n'

# Portability lint: bash's =~ uses the system regcomp, and on macOS (BSD libc)
# the GNU escapes \b \w \s \d \< \> are not special, so a match silently fails.
# Checks inline =~ literals and the assignments of every variable used as
# `=~ $name`. jq regexes (Oniguruma) are not affected and not checked.
gnu_esc='\\[bwsd<>]'
lint_fail=0
for f in "$ROOT"/hooks/*.sh "$ROOT"/hooks/lib/*.sh; do
  rel="${f#"$ROOT"/}"
  while IFS= read -r hit; do
    printf 'FAIL %s: GNU-only regex escape after =~: %s\n' "$rel" "$hit"; lint_fail=1
  done < <(grep -nE '=~ +[^$ ]' "$f" | grep -E "$gnu_esc")
  for v in $(grep -oE '=~ +\$\{?[A-Za-z_][A-Za-z0-9_]*' "$f" | sed -E 's/.*\$\{?//' | sort -u); do
    while IFS= read -r hit; do
      printf 'FAIL %s: GNU-only regex escape in $%s: %s\n' "$rel" "$v" "$hit"; lint_fail=1
    done < <(grep -nE "(^|[^A-Za-z0-9_])$v=" "$f" | grep -E "$gnu_esc")
  done
done
[ "$lint_fail" -eq 0 ] && printf 'ok   no GNU-only escapes in =~ regexes under hooks/\n'
[ "$lint_fail" -eq 0 ] || fail=1

# Drift check 7: hooks/tiered.md and skills/tier/SKILL.md agree on what
# `"model": "off"` does (the tier_model /config default handed back to Jev).
need "hooks/tiered.md" \
  'hands a /config `tier_model` default' "model override hand-back (tiered.md)"
need "skills/tier/SKILL.md" \
  'hands a /config `tier_model` default' "model override hand-back (SKILL.md)"

[ "$fail" -eq 0 ] && printf 'ok   all shared rule copies aligned\n'
exit $fail
