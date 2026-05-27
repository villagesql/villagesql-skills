# VillageSQL Project Context

VillageSQL is a MySQL tracking fork with the VillageSQL Extension Framework (VEF) —
a system for building custom SQL functions and types without modifying server code.
Extensions are packaged as `.veb` files and installed at runtime.

Key repos (cloned locally — check `AGENTS.local.md` for machine-specific paths):
- `villagesql-server/` — core MySQL fork with VEF
- `vsql-ai/`, `vsql-crypto/`, `vsql-uuid/`, `vsql-network-address/`, `vsql-http/`, `vsql-cube/` — official extensions
- `villagesql-docs/` — Mintlify documentation (villagesql.com/docs)
- `villagesql-website/` — Eleventy marketing site (villagesql.com)

Server default socket: `/tmp/mysql.sock`, port 3306. Verify the actual socket
from `pgrep -a mysqld` output before connecting. Check `AGENTS.local.md` for
machine-specific overrides.

## Commit Standards

- Summary line ≤41 characters, imperative mood, no period
- Body lines ≤72 characters, explain WHY not WHAT
- End with `AI=GEMINI` and `Co-Authored-By: Gemini <noreply@google.com>`
- Run `villint.sh` before committing server code
- Never push directly to `main`; never create PRs (stop at push)

## Key Rules

- All behavioral claims about the server require a live query to verify
- Every claim in a blog post or doc must trace to a merged PR, live query result,
  or explicit engineer statement
- Before finishing any task, check whether other repos reference the same term,
  path, or API
- Use `git -C /path <subcommand>` — never `cd /path && git`
