#!/usr/bin/env bash
set -euo pipefail
mkdir -p lib

cat > lib/net.py <<'PY'
"""Networking helpers."""

import time


def fetch_with_retry(url, attempts=4, base_delay=0.5):
    """Fetch url, retrying with exponential backoff on failure.

    Retries until `attempts` total tries are used, doubling the delay each
    time starting from `base_delay` seconds, then re-raises on the last one.
    """
    delay = base_delay
    for attempt in range(attempts):
        try:
            return _do_fetch(url)
        except ConnectionError:
            if attempt == attempts - 1:
                raise
            time.sleep(delay)
            delay *= 2
    raise ConnectionError(url)


def _do_fetch(url):
    raise NotImplementedError
PY

if command -v git >/dev/null 2>&1; then
  git init -q
fi
