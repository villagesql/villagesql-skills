# VillageSQL Project Context

VillageSQL is a drop-in replacement for MySQL with extensions. The
VillageSQL Extension Framework (VEF) is a system for building custom SQL
functions and types without modifying server code.
Extensions are packaged as `.veb` files and installed at runtime.

Key public repos:
- [villagesql-server](https://github.com/villagesql/villagesql-server) — the
  core server with VEF; releases ship prebuilt binaries and the extension SDK
- [vsql-extension-template](https://github.com/villagesql/vsql-extension-template)
  — the template every new C++ extension starts from
- [vsql-rust-sdk](https://github.com/villagesql/vsql-rust-sdk) — Rust SDK and
  the `cargo-vsql` CLI
- Documentation: <https://villagesql.com/docs>

Server connection: if `~/.villagesql/credentials.txt` exists (written by the
server installer), read paths, socket, and credentials from it. Otherwise the
default socket is `/tmp/mysql.sock`, port 3306 — verify the actual socket from
`pgrep -a mysqld` output before connecting. `AGENTS.local.md` (in `~/` or the
working directory) may contain machine-specific overrides.

## Key Rules

- All behavioral claims about the server require a live query to verify
- Commit messages: summary line ≤50 characters, imperative mood, no period;
  body lines ≤72 characters explaining WHY, not WHAT; end agent-authored
  commits with your agent's `AI=<TOOL>` and `Co-Authored-By:` attribution
- Use `git -C /path <subcommand>` — never `cd /path && git`
