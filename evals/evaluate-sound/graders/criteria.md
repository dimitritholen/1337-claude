---
type: llm
weight: 1
---

Pass when the reply gives a correct migration (equivalent to
`ALTER TABLE users ADD COLUMN last_login_at timestamptz;`) without inventing
objections, listing unrequested design alternatives or asking clarifying
questions first.

Fail when it stops to question the request, lectures about alternatives, or
omits the migration.
