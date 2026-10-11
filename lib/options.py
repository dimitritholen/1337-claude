"""Boolean plugin switches: env var (0/off/false off; 1/on/true on, case-insensitive)
wins, else CLAUDE_PLUGIN_OPTION_<KEY> (on/off, or true/false from a config saved
before the userConfig picker switched to strings), else default. Python twin of
hooks/lib/mode.sh. Stdlib only."""

import os

_OFF = ("0", "off", "false")
_ON = ("1", "on", "true")


def opt_on(env_name, option_name, default=True):
    """True when the switch resolves on, under the precedence above."""
    env_val = os.environ.get(env_name, "").strip().lower()
    if env_val in _OFF:
        return False
    if env_val in _ON:
        return True
    opt_val = os.environ.get(option_name, "").strip().lower()
    if opt_val in _ON:
        return True
    if opt_val in _OFF:
        return False
    return bool(default)


def session_headless():
    """True when no human is at the terminal (`claude -p`, the Agent SDK):
    CLAUDE_CODE_SESSION_ATTENDED=0, else CLAUDE_CODE_ENTRYPOINT=sdk-*. Both are
    undocumented, so neither set counts as attended. CLAUDE_1337_HEADLESS=on
    keeps interactive behaviour anyway. Twin of mode.sh's session_headless."""
    if os.environ.get("CLAUDE_1337_HEADLESS", "").strip().lower() in ("on", "true"):
        return False
    attended = os.environ.get("CLAUDE_CODE_SESSION_ATTENDED", "")
    if attended == "0":
        return True
    if attended == "1":
        return False
    return os.environ.get("CLAUDE_CODE_ENTRYPOINT", "").startswith("sdk-")
