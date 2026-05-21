# PostgreSQL Port Guide

Load this file at the start of Phase 1 when `pg_port: true` is recorded in
`architecture.md`. It governs every design decision for the duration of the
port — read it before researching the source extension.

## Pre-Port Analysis (do this before architecture.md)

Before designing anything, enumerate the source extension's full function list.
For each function, categorize it:

| Category | Meaning |
|---|---|
| **Full** | Implementable with exact semantics under current VEF |
| **Workaround** | Implementable but with a meaningful behavioral difference (e.g. returns comma-separated string instead of a row set) |
| **Blocked** | Not implementable under current VEF — document in `limitations.md` immediately |

Record this table in `.claude/tracking/architecture.md` under a
`## PostgreSQL Function Map` heading. Never start writing C++ until the
full map exists — missing functions discovered during Phase 3 cause
expensive rework.

**Blocked categories to check immediately:**
- Set-returning functions (SRFs like `skeys()`, `svals()`, `each()`) — VEF
  has no row-set return mechanism; workaround is comma-separated string or JSON array
- Functions requiring catalog or system table access — not available to extensions
- Aggregate functions — probe in Phase 3 step 3; treat as tentative-blocked until confirmed
- Functions using PostgreSQL-internal types with no MySQL equivalent

## Type Mapping

| PostgreSQL type | MySQL/VEF type | Notes |
|---|---|---|
| `text`, `varchar` | VEF `STRING` | Use `VARCHAR(N)` in DDL; pick N based on domain |
| `bytea` | VEF `BINARY` / `VARBINARY` | |
| `boolean` | `TINYINT(1)` or `INT` | MySQL has no native boolean; return 1/0 |
| `integer`, `int4` | `INT` | |
| `bigint`, `int8` | `BIGINT` | |
| `real`, `float4` | `FLOAT` | |
| `double precision`, `float8` | `DOUBLE` | |
| `numeric`, `decimal` | `DECIMAL(M,D)` | Choose precision from domain |
| `uuid` | vsql-uuid `uuid` type if available; else `BINARY(16)` | |
| `json`, `jsonb` | MySQL native `JSON` | |
| `timestamp` | `DATETIME` | MySQL DATETIME has no timezone |
| `timestamptz` | `DATETIME` — document timezone loss in README | |
| `interval` | `BIGINT` (seconds) or formatted `VARCHAR` — choose based on use | |
| Custom/opaque type | VEF custom type with binary storage | |

When a PostgreSQL type has no clean MySQL equivalent, document the mapping
decision in `architecture.md` and note it in README under Known Limitations.

## NULL Semantics

MySQL propagates NULL by default: if any required argument is NULL, the
function returns NULL. This matches PostgreSQL's `CALLED ON NULL INPUT`
default.

**Rules:**
- Always check `arg->is_null` first (pre-implementation invariant — already
  required). Return `IS_NULL` immediately for any required argument that is NULL.
- Exception: functions that are explicitly NULL-safe in PostgreSQL (e.g.
  `COALESCE`-like behavior) — preserve that semantic, document it in the
  function reference.
- Do NOT silently coerce NULL to a default value (e.g., treating NULL as
  empty string). If the PostgreSQL function does this, document it explicitly.

## Error Handling

PostgreSQL raises exceptions (`ereport(ERROR, ...)`). MySQL convention is
different — functions return NULL with a warning, or use the VEF error
mechanism for hard failures.

**Decision table:**

| Situation | MySQL idiom |
|---|---|
| Invalid input format (e.g. malformed value) | Return NULL; use VEF warning/error if available |
| Out-of-range value | Return NULL; document the valid range |
| Argument type mismatch caught at build time | Compile error via VEF typed API — no runtime check needed |
| Internal invariant violation (should never happen) | VEF error mechanism with descriptive message |
| Truncation due to output buffer limit | Return NULL or truncated value + warning — document which |

Never silently succeed with wrong output. If the correct answer isn't
returnable, return NULL and use the VEF error/warning mechanism.

## Operator → Function Translation

PostgreSQL extensions use operators that have no MySQL SQL syntax equivalent.
Every operator must become a named function. Apply MySQL's `TYPE_VERB` or
`TYPE_PREDICATE` naming pattern.

| PostgreSQL operator | Semantics | MySQL function name pattern |
|---|---|---|
| `->` | Key/field access | `<type>_get(val, key)` |
| `->>` | Key/field access returning text | `<type>_get_text(val, key)` |
| `?` | Key existence | `<type>_exists(val, key)` or `<type>_has_key(val, key)` |
| `?&` | All keys exist | `<type>_has_all_keys(val, keys)` |
| `?\|` | Any key exists | `<type>_has_any_key(val, keys)` |
| `\|\|` | Concatenation/merge | `<type>_concat(a, b)` or `<type>_merge(a, b)` |
| `-` with key arg | Delete key | `<type>_delete(val, key)` |
| `-` with value arg | Delete by value | `<type>_delete_val(val, value)` |
| `@>` | Contains | `<type>_contains(val, other)` |
| `<@` | Contained by | `<type>_contained_by(val, other)` |
| `&&` | Overlap | `<type>_overlaps(a, b)` |
| `=` (type equality) | Equality | `<type>_equal(a, b)` — also needed internally for VEF |
| `<>` (type inequality) | Inequality | `<type>_not_equal(a, b)` |
| `<`, `>`, `<=`, `>=` | Ordering | `<type>_lt`, `_gt`, `_lte`, `_gte` |

**Naming rules:**
- The type prefix is the extension's canonical type name, not the PostgreSQL
  extension name (e.g. `hstore_get`, not `hstore_ext_get`).
- Boolean-returning functions use adjective form: `hstore_contains`,
  `inet_within`, not `hstore_is_contained`, `inet_is_within`.
- Avoid reserved words as function names: `keys`, `values`, `check`,
  `table`, `index`, `select`, `delete`, `replace`, `insert`.
  Use `<type>_keys`, `<type>_vals` instead.

## Set-Returning Functions

PostgreSQL SRFs (`each()`, `skeys()`, `svals()`, unnest functions) return
multiple rows. VEF has no row-set return mechanism.

**Standard workaround:** return a comma-separated string or JSON array from
a scalar function. Document this prominently in the README and Known
Limitations.

Example: PostgreSQL's `skeys(hstore)` returns one row per key. MySQL port:
`hstore_keys(val)` returns `'key1,key2,key3'` as a VARCHAR.

Add a `limitations.md` entry immediately: note that SRFs are blocked by VEF,
name the affected functions, and describe the workaround offered.

## Strict Mode

MySQL's strict mode (`sql_mode=STRICT_TRANS_TABLES`) affects INSERT/UPDATE
behavior, not function evaluation. Your extension runs under whatever
`sql_mode` the user has set.

**Rules:**
- Design validation to happen at parse/store time, not retrieval time. If
  the extension stores encoded binary, validate the input in the store
  function and return NULL on invalid input — don't defer to retrieval.
- Do not assume the user has strict mode off. Test with strict mode on.
- If the extension's behavior differs by strict mode, document it.

## String and Charset Handling

MySQL strings carry charset and collation metadata. PostgreSQL strings are
encoding-aware but treat collation differently.

**Rules:**
- If the extension performs string comparison, document whether it is
  case-sensitive. MySQL's default collation (`utf8mb4_0900_ai_ci`) is
  case-insensitive; byte-for-byte comparisons are case-sensitive.
- If the function is inherently case-sensitive (e.g., key lookup in a
  key-value store), say so explicitly in the function reference.
- For string output functions: use `utf8mb4` for any output that may
  contain non-ASCII data. Don't assume ASCII.
- Test with multi-byte input (e.g., Japanese, emoji) if the function
  handles arbitrary string keys or values.

## What to Put in the README for PostgreSQL Users

Add a **"Migrating from PostgreSQL"** section to README.md that covers:

1. Function name mapping table (PG name → VillageSQL name) for every function
   that was renamed.
2. Operators: explicit note that `->`, `?`, `||` etc. are not available; show
   the equivalent named function for each.
3. Behavioral differences: NULL handling, error behavior, type differences,
   any strict-mode implications.
4. Missing functions: list every Blocked function from the function map, with
   a one-line explanation of why it isn't available and what the closest
   workaround is.

This section is the primary migration aid for developers coming from
PostgreSQL. Write it to be scannable: a two-column table for name mapping,
then prose for behavioral differences.
