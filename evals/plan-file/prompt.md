---
max_turns: 8
allowed_tools: [Write, Read, Glob, Grep]
---

/1337:plan Add a `--json` flag so `list` prints machine-readable output that
a script can pipe into jq. The whole CLI is this one file, `todo.py`, and
there is no tasqx here — record the plan as `plans/list-json.md`:

```python
import argparse, json, pathlib

DB = pathlib.Path.home() / ".todo.json"

def load():
    return json.loads(DB.read_text()) if DB.exists() else []

def save(items):
    DB.write_text(json.dumps(items))

def cmd_add(args):
    items = load()
    items.append({"id": len(items) + 1, "text": args.text, "done": False})
    save(items)

def cmd_list(args):
    for it in load():
        print(f"[{'x' if it['done'] else ' '}] {it['id']} {it['text']}")

p = argparse.ArgumentParser()
sub = p.add_subparsers(dest="cmd", required=True)
a = sub.add_parser("add"); a.add_argument("text"); a.set_defaults(fn=cmd_add)
l = sub.add_parser("list"); l.set_defaults(fn=cmd_list)
args = p.parse_args(); args.fn(args)
```
