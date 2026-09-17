---
max_turns: 5
allowed_tools: [Read, Glob, Grep]
---

Write a PostgreSQL migration that adds a nullable `last_login_at timestamptz`
column to the `users` table.
