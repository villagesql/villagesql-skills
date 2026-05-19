# VEF Capability Discovery

Do not assume limitations from prior knowledge. Probe the SDK and the
running server.

## Header-discoverable (Phase 2 bootstrap)

Assess all capabilities from the typed API headers (`vsql.h` and the
`vsql/` subdirectory).

- **Storage model.** Does the type builder expose only fixed-length
  storage, or also variable-length? For fixed-length, the persisted length
  sets the storage size and encode must write exactly that many bytes;
  returning 0 via the length output parameter signals an error. If only
  fixed-length is available, size to your practical maximum, write data +
  zero-padding, embed an in-band length header, and document in README.

- **Parameterized types.** Does the SDK expose registration functions for
  types that accept `TYPE(N)` or `TYPE('key=value')` arguments? Look for
  two registration flavors (integer shorthand and key=value string) and
  the struct that carries parameter data from server to extension. Record
  exact names. The canonical example is
  `villagesql/examples/vsql-tvector/src/tvector.cc` in the server source
  tree.

- **Index registration.** Is an index registration API present? If not,
  custom type columns cannot be indexed — do not design around index-based
  lookup.

- **Max VDF parameters.** Read the max-parameter constant. Functions
  needing more inputs must use structured types or be split.

- **Preview capabilities.** Headers under a `preview/` subdirectory are
  preview capabilities — documented but unstable across server builds.
  They may include column storage, index hooks, system variables, and
  background threads. If a preview API is needed, record it in
  `.claude/tracking/limitations.md` so it surfaces in the README.

## Behavior-discoverable (after first install in Phase 3)

These can't be probed in Phase 1 because no extension is installed yet.
Run them as part of Phase 3 once the extension is built and installed for
the first time, and record results in `.claude/tracking/limitations.md`.

- **Aggregate functions.** Create a custom type column and test `SUM` or
  `AVG`. If they fail, only `COUNT(DISTINCT)`, `MIN`, `MAX`, and
  `GROUP_CONCAT` are safe — document this constraint.

- **Extension upgrade path.** Test `ALTER EXTENSION` or equivalent. If it
  doesn't exist, type changes require `UNINSTALL` + `INSTALL` — document
  for users.
