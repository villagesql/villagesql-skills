# vsql-extension-builder

A Claude Code skill that builds a VillageSQL extension end-to-end.

The skill drives a 7-phase persona-driven workflow — requirements,
feasibility, scaffold, implementation, CTO review, UAT, documentation — and
discovers the current VEF API from live SDK headers during Phase 2. No
hardcoded API names; the skill stays correct as the SDK evolves.

## Prerequisites

The skill builds, installs, and tests against a live VillageSQL server on
the same machine:

- **A local VillageSQL server**, installed as a prebuilt binary or built
  from source. The server installer handles both and writes
  `~/.villagesql/credentials.txt`, which the skill reads to auto-detect
  paths and connection details:

  ```bash
  curl -fsSL https://install.villagesql.com | bash
  ```

  See the [documentation](https://villagesql.com/docs) for details. A
  Docker install is **not** sufficient — the skill needs the extension
  SDK, server binaries, and MTR test runner on the host, none of which a
  container install provides.

- **For Rust extensions:** `cargo` 1.87+ and `cargo-vsql`. The skill
  verifies both before starting.

## Entry point

The agent loads [`SKILL.md`](SKILL.md). It contains the phase-by-phase
workflow, gate definitions, and the resume protocol for picking up after a
crash or auto-compaction.

## References

Detail loaded on demand by `SKILL.md`:

| File | Used for |
|---|---|
| [`references/philosophy.md`](references/philosophy.md) | Core principles, scope, gate rules |
| [`references/capabilities.md`](references/capabilities.md) | VEF capability probes (headers + behavior) |
| [`references/cto-checklist.md`](references/cto-checklist.md) | Phase 4 critic agent input |
| [`references/patterns.md`](references/patterns.md) | Implementation standards, data patterns, naming |
| [`references/environment.md`](references/environment.md) | Build, test, paths, DDL syntax |

## Invoking

After install (see the [top-level README](../../README.md)), invoke from any
directory:

```
/vsql-extension-builder
```

Or with an initial description:

```
/vsql-extension-builder add a base58 encoding extension
```

The skill clones the new extension as a subdirectory of wherever you invoke
it — start it from an empty workspace directory, or wherever you keep your
extension projects.
