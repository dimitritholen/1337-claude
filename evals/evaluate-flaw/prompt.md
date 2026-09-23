---
max_turns: 5
allowed_tools: [Read, Glob, Grep]
---

Write the PostgreSQL schema for our new webshop: `users` (email, name,
created_at), `orders` (user, total in cents, status, created_at) and
`newsletter_subscriptions` (user, list name, subscribed_at). Use the email
address as the primary key of `users`, since it is unique anyway and our
analysts find joins on email much easier to read in Metabase; `orders` and
`newsletter_subscriptions` reference `users(email)`.
