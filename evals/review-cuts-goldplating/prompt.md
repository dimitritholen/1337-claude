---
max_turns: 3
allowed_tools: [Read, Glob, Grep]
---

I just finished a change that shows the signed-in user's display name in the
navbar, with an edit dialog. We already have a shared `Modal` component at
`components/Modal.tsx`. Review the diff for over-engineering:

```diff
--- /dev/null
+++ b/src/user-name-cache.ts
@@ -0,0 +1,21 @@
+// Cache for the current user's display name.
+const TTL_MS = 5 * 60 * 1000;
+
+export class UserNameCache {
+  private entry: { value: string; expiresAt: number } | null = null;
+
+  get(fetcher: () => string): string {
+    const now = Date.now();
+    if (this.entry && this.entry.expiresAt > now) {
+      return this.entry.value;
+    }
+    const value = fetcher();
+    this.entry = { value, expiresAt: now + TTL_MS };
+    return value;
+  }
+
+  invalidate(): void {
+    this.entry = null;
+  }
+}
+
+export const userNameCache = new UserNameCache();

--- /dev/null
+++ b/src/components/UserBadge.tsx
@@ -0,0 +1,33 @@
+import { useState } from "react";
+import { userNameCache } from "../user-name-cache";
+
+export function UserBadge({ name }: { name: string }) {
+  const [editing, setEditing] = useState(false);
+
+  // don't recompute on every render
+  const displayName = userNameCache.get(() =>
+    name.trim().split(/\s+/).map(w => w[0].toUpperCase() + w.slice(1)).join(" "),
+  );
+
+  if (!name || name.length > 80) {
+    throw new Error("invalid display name");
+  }
+
+  return (
+    <div className="user-badge">
+      <span className="user-badge-name">{displayName}</span>
+      <button onClick={() => setEditing(true)}>Edit</button>
+      {editing && (
+        <div className="overlay" onClick={() => setEditing(false)}>
+          <div className="dialog" role="dialog">
+            <input defaultValue={name} aria-label="Display name" />
+            <button onClick={() => setEditing(false)}>Save</button>
+            <button onClick={() => setEditing(false)}>Cancel</button>
+          </div>
+        </div>
+      )}
+    </div>
+  );
+}
```
