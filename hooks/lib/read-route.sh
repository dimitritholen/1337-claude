# Outputs routing text for a refused read or Grep/Glob call. Used by
# hooks/orchestrator-guard.sh (Bash read refusals) and hooks/read-cap.sh
# (Read/Grep/Glob cap refusals) to keep the same message in both places.
read_route() {
  if command -v ripwire >/dev/null 2>&1; then
    printf '%s' 'Free instead: `git status`, `git diff --stat`, `ls`, or `ripwire <dir> --for="<what you are after>" --legend=compact` (then `--expand=SYM`, `--callers=SYM`, `--impact=SYM`, `--uses=SYM`, `--grep=STR`).
For anything else (config, lockfile, transcript, prose), or when the file contents themselves are wanted: dispatch 1337:scout with the question; it reads in its own context.'
  else
    printf '%s' 'Free instead: `git status`, `git diff --stat`, `ls`.
Dispatch 1337:scout with the question; it reads in its own context.'
  fi
}
