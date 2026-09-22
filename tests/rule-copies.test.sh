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

# The two ways forward out of a refused read: the read-cap hook and the
# orchestrator guard say it in the same words.
for f in hooks/read-cap.sh hooks/orchestrator-guard.sh; do
  need "$f" 'For code: `ripwire <dir> --for="<what you are after>" --legend=compact`' "ripwire route"
  need "$f" 'dispatch 1337:scout with the question; it reads in its own context.' "scout route"
done

# The skills express the same never-cut rule in review voice.
for f in skills/review/SKILL.md skills/audit/SKILL.md; do
  need "$f" "never over-engineering" "never-cut rule"
done

[ "$fail" -eq 0 ] && printf 'ok   all shared rule copies aligned\n'
exit $fail
