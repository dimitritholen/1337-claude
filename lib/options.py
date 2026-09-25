"""Boolean plugin switches: env var (0/off/false off; 1/on/true on, case-insensitive)
wins, else CLAUDE_PLUGIN_OPTION_<KEY>, else default. Python twin of hooks/lib/mode.sh.
Stdlib only."""

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
    opt_val = os.environ.get(option_name, "")
    if opt_val == "true":
        return True
    if opt_val == "false":
        return False
    return bool(default)
