---
name: oracle-upstream-skills
description: Pointer to Oracle's official skills for Oracle Database, SQLcl, ORDS, and APEX (github.com/oracle/skills). Use when a task needs deep Oracle Database/SQLcl/ORDS/APEX knowledge beyond this repo's own scripts and docs — e.g. writing/tuning SQL or PL/SQL, designing ORDS REST APIs, using SQLcl's Liquibase/DIFF/MCP features, or APEX application generation.
---

# Oracle Upstream Skills

This repo intentionally does **not** vendor a copy of Oracle's official skill files — that content is
maintained upstream, changes frequently, and already has its own install mechanism. Use this file only as
a router to the right upstream skill/topic; read the upstream files directly (or install them) rather than
expecting a local copy here.

## Where to look

Oracle publishes and maintains these at [github.com/oracle/skills](https://github.com/oracle/skills)
(UPL-1.0 licensed):

| Topic in this repo | Upstream skill/category |
| --- | --- |
| SQLcl (`sql` CLI, connections, DIFF, Liquibase, MCP server) — see `scripts/util/save-sqlcl-connection.sh` etc. | [`db/sqlcl/`](https://github.com/oracle/skills/tree/main/db/sqlcl) |
| ORDS (REST APIs, PL/SQL Gateway, auth, install) — see `local-26ai-ords` container, `ords-config/` | [`db/ords/`](https://github.com/oracle/skills/tree/main/db/ords) |
| General SQL / PL/SQL / DB admin / performance / security / containers | [`db/SKILL.md`](https://github.com/oracle/skills/blob/main/db/SKILL.md) (routing table to `db/plsql`, `db/sql-dev`, `db/admin`, `db/performance`, `db/security`, `db/containers`, etc.) |
| APEX application development (APEXlang generation) | [`apex/SKILL.md`](https://github.com/oracle/skills/blob/main/apex/SKILL.md) |

## How to use it

- **Already installed for you?** Check whether `db`/`apex`/`ords`/`sqlcl` skills already appear in your
  assistant's skill list (they may already be installed at the user level, e.g.
  `~/.copilot/skills/db/SKILL.md`) — if so, just read/use them directly, no install needed.
- **Not installed?** Oracle provides an installer: `npx skills add oracle/skills/db` (covers `ords` and
  `sqlcl` as subdirectories) and `npx skills add oracle/skills/apex`. See the repo's
  [README](https://github.com/oracle/skills#installation) for Claude Code plugin-marketplace instructions
  too.
- Prefer the upstream skill for anything that is **generic Oracle Database/SQLcl/ORDS/APEX** knowledge (SQL
  syntax, PL/SQL patterns, ORDS REST design, APEX generation). Use this repo's own skills
  (`repo-conventions`, `adb-db-install`, `db-upgrade`) for anything **specific to how this repo's containers,
  scripts, and compose files are wired**.
