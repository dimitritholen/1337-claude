#!/usr/bin/env bash
# Tests for design-systems/meridian/tools/export.mjs: every template exports
# to one self-contained file, export works from a read-only copy of the
# design-system dir, bad arguments exit non-zero, and nothing is written
# under design-systems/. Needs node; no key, no network.
set -u

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)"
DS="$ROOT/design-systems/meridian"
fail=0
work="$(mktemp -d)"
trap 'chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"' EXIT

pass() { printf 'ok   %s\n' "$1"; }
flunk() { printf 'FAIL %s\n' "$1"; fail=1; }
check_code() { if [ "$2" -eq "$3" ]; then pass "$1"; else flunk "$1 (exit $2, want $3): $(cat "$work/stderr")"; fi; }

if ! command -v node >/dev/null 2>&1; then
    printf 'todo design-systems: node not installed\n'
    exit 0
fi

before="$(cd "$ROOT" && find design-systems -type f -newer "$DS/tools/export.mjs" 2>/dev/null; git status --porcelain --untracked-files=all -- design-systems | sort)"

# --- each template exports to a self-contained file -----------------------------
check_export() { # label file
    if [ ! -s "$2" ]; then flunk "$1: output written"; return; fi
    pass "$1: output written"
    if grep -q 'assets/' "$2"; then flunk "$1: no assets/ references left"; else pass "$1: no assets/ references left"; fi
    if grep -q '@font-face' "$2" && grep -q 'data:font/woff2;base64,' "$2"; then pass "$1: fonts embedded"; else flunk "$1: fonts embedded"; fi
    if grep -q 'Embedded font licenses' "$2"; then pass "$1: font licenses retained"; else flunk "$1: font licenses retained"; fi
}

for f in "$DS"/templates/*.html; do
    t="$(basename "$f" .html)"
    (cd "$work" && node "$DS/tools/export.mjs" "$f" "out/$t.html") >/dev/null 2>"$work/stderr"
    check_code "export $t.html: exit 0" "$?" 0
    check_export "export $t.html" "$work/out/$t.html"
done
[ -f "$DS/templates/codebase-guide.html" ] && pass "codebase-guide.html template present" || flunk "codebase-guide.html template present"

# --- read-only copy of the design-system dir -----------------------------------
cp -R "$DS" "$work/ro"
chmod -R a-w "$work/ro"
(cd "$work" && node "$work/ro/tools/export.mjs" "$work/ro/templates/digest.html" "$work/ro-out.html") >/dev/null 2>"$work/stderr"
check_code "read-only dir: exit 0" "$?" 0
check_export "read-only dir" "$work/ro-out.html"
extra="$(cd "$work/ro" && find . \( -newer "$work/ro-out.html" -o -name dist \) -print)"
if [ -z "$extra" ]; then pass "read-only dir: nothing written inside"; else flunk "read-only dir: nothing written inside ($extra)"; fi

# --- bad arguments ---------------------------------------------------------------
node "$DS/tools/export.mjs" "$DS/templates/index.html" >/dev/null 2>"$work/stderr"
code=$?; if [ "$code" -ne 0 ] && grep -q 'Usage' "$work/stderr"; then pass "missing output arg: exits non-zero with usage"; else flunk "missing output arg: exits non-zero with usage (exit $code)"; fi
node "$DS/tools/export.mjs" >/dev/null 2>"$work/stderr"
code=$?; if [ "$code" -ne 0 ]; then pass "no args: exits non-zero"; else flunk "no args: exits non-zero"; fi
node "$DS/tools/export.mjs" "$DS/README.md" "$work/x.html" >/dev/null 2>"$work/stderr"
code=$?; if [ "$code" -ne 0 ] && grep -q '.html file' "$work/stderr"; then pass "non-.html input: exits non-zero"; else flunk "non-.html input: exits non-zero (exit $code)"; fi
node "$DS/tools/export.mjs" "$work/missing.html" "$work/x.html" >/dev/null 2>"$work/stderr"
code=$?; if [ "$code" -ne 0 ] && grep -q 'not found' "$work/stderr"; then pass "missing input: exits non-zero"; else flunk "missing input: exits non-zero (exit $code)"; fi

# --- nothing written under design-systems/ -----------------------------------------
after="$(cd "$ROOT" && find design-systems -type f -newer "$DS/tools/export.mjs" 2>/dev/null; git status --porcelain --untracked-files=all -- design-systems | sort)"
if [ "$before" = "$after" ]; then pass "design-systems/ untouched by exports"; else flunk "design-systems/ untouched by exports"; fi
if [ ! -e "$DS/dist" ]; then pass "no dist/ under design-systems/meridian"; else flunk "no dist/ under design-systems/meridian"; fi

exit $fail
