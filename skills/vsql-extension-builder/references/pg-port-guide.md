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
| **Workaround** | Implementable but with a meaningful behavioral difference (e.g. returns JSON array instead of a row set) |
| **Blocked** | Not implementable under current VEF — document in `limitations.md` immediately |

Record this table in `.claude/tracking/architecture.md` under a
`## PostgreSQL Function Map` heading. Never start writing C++ until the
full map exists — missing functions discovered during Phase 3 cause
expensive rework.

**Also run this pre-port checklist before categorizing — each "yes" requires
special handling described later in this guide:**

- [ ] Does the source extension use set-returning functions (SRFs)?
- [ ] Does it use catalog or system table access?
- [ ] Does it define aggregate functions?
- [ ] Does it use `CHECK` constraints or validation at the constraint layer?
- [ ] Does it provide trigger functions?
- [ ] Does it use `DEFAULT` expressions that call functions?
- [ ] Does it maintain per-connection or per-session state?
- [ ] Does it mark functions as `IMMUTABLE` for index optimization?
- [ ] Does it process large data structures that could exceed `max_allowed_packet`?
- [ ] Does it use PostgreSQL-internal types with no MySQL equivalent?

**Blocked categories:**
- Set-returning functions (SRFs) — VEF has no row-set return; use JSON array workaround
- Catalog/system table access — not available to extensions
- Aggregate functions — probe in Phase 3 step 3; treat as tentative-blocked until confirmed
- Trigger functions — MySQL triggers are SQL-only; cannot delegate to extension functions
- CHECK constraint validators — MySQL 8.0.16+ enforces CHECK but cannot call UDFs from them

## Type Mapping

| PostgreSQL type | MySQL/VEF type | Notes |
|---|---|---|
| `text`, `varchar` | VEF `STRING` | Use `VARCHAR(N)` in DDL; pick N based on domain |
| `bytea` | VEF `BINARY` / `VARBINARY` | Binary-safe; do not use `VARCHAR` for binary data |
| `boolean` | `TINYINT(1)` | MySQL has no native boolean. `TINYINT(1)` accepts any integer — **enforce 0/1 in C++ code**; MySQL will not restrict storage |
| `integer`, `int4` | `INT` | |
| `bigint`, `int8` | `BIGINT` | Signed max: 2^63−1. PostgreSQL `bigint` has the same limit but `numeric` does not — see below |
| `real`, `float4` | `FLOAT` | Single-precision (32-bit). Use `DOUBLE` if the source extension requires more precision — MySQL `FLOAT` is lossy for values exceeding ~7 significant digits |
| `double precision`, `float8` | `DOUBLE` | IEEE 754 64-bit, same as PostgreSQL |
| `numeric`, `decimal` | `DECIMAL(M,D)` | MySQL max: M=65, D=30. PostgreSQL `numeric` is arbitrary-precision — document overflow behavior if the source uses values outside this range |
| `uuid` | vsql-uuid `uuid` type if available; else `BINARY(16)` | `BINARY(16)` comparisons are lexicographic byte order, not UUID RFC 4122 sort order — document this if ordering matters |
| `json`, `jsonb` | MySQL native `JSON` | MySQL JSON is always stored as UTF-8 internally; charset conversion is automatic |
| `timestamp` | `DATETIME` | MySQL `DATETIME` has no timezone field — stores local time as given, no UTC conversion |
| `timestamptz` | `DATETIME` | **What is lost:** the original UTC offset is discarded entirely. The stored value is whatever wall-clock time was passed in. Document this explicitly; suggest callers normalize to UTC before storing |
| `interval` | `BIGINT` (milliseconds) | Milliseconds preserve sub-second precision. Seconds lose it. Avoid `VARCHAR` — it forces callers to parse. Document the unit in the function reference |
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
- Division by zero in MySQL returns NULL + warning (not an error). Follow
  this pattern for analogous numeric edge cases in the port.

## Error Handling

PostgreSQL raises exceptions (`ereport(ERROR, ...)`). MySQL convention is
different: functions return NULL for bad input, and use the server's warning
or error mechanism for failures.

**Important:** The VEF warning/error mechanism must be verified during Phase 2
bootstrap — confirm what API is available before designing error behavior. If
no warning API exists, return NULL and document the silent failure in the
function reference.

**Decision table:**

| Situation | MySQL idiom |
|---|---|
| Invalid input format (e.g. malformed value) | Return NULL. Emit a VEF warning if the API supports it — verify during Phase 2. Document in function reference |
| Out-of-range value | Return NULL. The C++ code must do the bounds check — MySQL will not catch it. Document valid range in function reference |
| Argument type mismatch caught at build time | Compile error via VEF typed API — no runtime check needed |
| Internal invariant violation (should never happen) | VEF error mechanism with descriptive message |
| Truncation due to output buffer limit | Return NULL. Never silently return truncated data — document the limit |
| Strict mode interaction | If the function is used in a generated column expression, strict mode may convert a NULL return into an INSERT error. Test with `GENERATED ALWAYS AS (my_func(...)) STORED` |

Never silently succeed with wrong output. If the correct answer isn't
returnable, return NULL.

**Note on warnings:** Do not assume callers run `SHOW WARNINGS` after a
function call — many frameworks suppress warnings silently. If an error
condition is important for callers to detect, return a sentinel value (e.g.
`-1` for integer functions) and document it, or require callers to validate
input before calling.

## Operator → Function Translation

PostgreSQL extensions use operators that have no MySQL SQL syntax equivalent.
Every operator must become a named function. Apply MySQL's `TYPE_VERB` or
`TYPE_PREDICATE` naming pattern.

| PostgreSQL operator | Semantics | MySQL function name pattern |
|---|---|---|
| `->` | Key/field access | `<type>_get(val, key)` |
| `->>` | Key/field access returning text | `<type>_get_text(val, key)` |
| `#>` | Deep path access | `<type>_get_path(val, path)` |
| `#>>` | Deep path access returning text | `<type>_get_path_text(val, path)` |
| `?` | Key existence | `<type>_has_key(val, key)` |
| `?&` | All keys exist | `<type>_has_all_keys(val, keys)` |
| `?\|` | Any key exists | `<type>_has_any_key(val, keys)` |
| `@?` | JSON path existence (PG 12+) | `<type>_path_exists(val, path)` |
| `@@` | JSON path match (PG 12+) | `<type>_path_match(val, path)` |
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
- Boolean-returning functions use adjective/verb form: `hstore_contains`,
  `inet_within` — not `hstore_is_contained`, `inet_is_within`.
- Avoid reserved words as function names: `keys`, `values`, `check`,
  `table`, `index`, `select`, `delete`, `replace`, `insert`, `update`.
  Use `<type>_keys`, `<type>_vals` instead.
- MySQL adds new built-in functions in patch releases. Before finalizing
  names, verify there are no conflicts with MySQL 8.0.x built-ins for the
  range of MySQL versions the extension will target.

## Set-Returning Functions

PostgreSQL SRFs (`each()`, `skeys()`, `svals()`, unnest functions) return
multiple rows. VEF has no row-set return mechanism.

**Standard workaround:** return a JSON array from a scalar function. JSON
is preferred over comma-separated strings because:
- Keys or values may contain commas — CSV requires an escaping scheme
- JSON is self-describing and easily parsed in application code
- MySQL 8.0+ has `JSON_TABLE()` for unpivoting JSON arrays into rows

Example: PostgreSQL's `skeys(hstore)` returns one row per key. MySQL port:
`hstore_keys(val)` returns `'["key1","key2","key3"]'` as a JSON array.

**If comma-separated strings are used** (e.g. for simpler types), define and
document the escaping scheme explicitly. Unescaped commas in values will
silently corrupt results.

**Ordering:** Commit to a documented order (insertion order, sorted, or
undefined) and test it. Callers may depend on ordering; silent changes will
break them.

**Type information loss:** SRF callers in PostgreSQL get typed columns.
MySQL callers get a JSON string they must parse. Document the element type
and structure explicitly in the function reference.

Add a `limitations.md` entry for every blocked SRF: name the function,
describe the workaround, and note that `JSON_TABLE()` can unpack the result
into rows if the caller needs relational output.

## Strict Mode and sql_mode

MySQL's `sql_mode=STRICT_TRANS_TABLES` affects INSERT/UPDATE behavior, not
function evaluation directly. However, strict mode interacts with extensions
in two ways:

**Direct interaction:**
- If the function is used in a generated column
  (`GENERATED ALWAYS AS (my_func(col)) STORED`), a NULL return from the
  function in strict mode will cause the INSERT to fail. Test this explicitly.
- If the function is called in a `CHECK` constraint expression — note that
  MySQL 8.0.16+ enforces CHECK but **cannot call user-defined functions from
  CHECK constraints**. Do not design validation around CHECK constraints.

**Other sql_mode settings that may affect behavior:**
- `NO_ZERO_DATE` / `NO_ZERO_IN_DATE` — affects DATETIME functions
- `ERROR_FOR_DIVISION_BY_ZERO` — turns the NULL+warning pattern into an error
- `ANSI_QUOTES` — changes how string literals are parsed; affects test files

**Rules:**
- Validate at parse/store time, not retrieval time.
- Do not assume the user has strict mode off. Test with strict mode on.
- If the extension's behavior differs by sql_mode, document it.

**UNSIGNED integer note:** MySQL has unsigned integer columns. If a function
accepts `INT` and the caller passes an `UNSIGNED INT`, MySQL auto-converts
silently regardless of strict mode. Design numeric functions to handle the
full unsigned range or document the limit.

## String and Charset Handling

MySQL strings carry charset and collation metadata. PostgreSQL strings are
encoding-aware but collation is a different concept.

**Rules:**
- If the extension performs string comparison, decide and document whether
  it is case-sensitive. The default MySQL collation (`utf8mb4_0900_ai_ci`)
  is case-insensitive; byte-for-byte comparisons are case-sensitive.
- If the function is inherently case-sensitive (e.g., key lookup in a
  key-value store), implement it as binary comparison in C++ and document it.
  Callers expecting case-insensitivity must use `LOWER()` themselves.
- Collation is per-column and per-connection (`SET NAMES`). Callers can
  override collation with `COLLATE` in the function call. The VEF extension
  receives the string bytes as given — it does not inherit the caller's
  collation. If your function must be collation-aware, verify during Phase 2
  bootstrap whether VEF exposes collation metadata; if not, document the
  limitation.
- For string output: use `utf8mb4`. Do not assume ASCII.
- For binary output (e.g. encrypted values, packed floats): use `VARBINARY`
  not `VARCHAR`. MySQL will apply charset conversion to `VARCHAR` output,
  which will corrupt binary data.
- JSON output is always UTF-8 internally in MySQL; no charset conversion
  needed in C++ code.
- Test with multi-byte input (Japanese, emoji) if the function handles
  arbitrary string keys or values.

## MySQL Behavioral Differences

These are MySQL behaviors that diverge from PostgreSQL and will cause
correctness bugs if not handled explicitly. Check each one against the
source extension before writing any C++.

**Implicit type conversion:**
MySQL converts types implicitly in ways PostgreSQL does not. `my_func(1)`
where `my_func` expects `VARCHAR` silently converts to `'1'`. Validate
argument types in C++ if precision or format matters — do not assume the
caller passed the right type.

**CHECK constraints cannot call UDFs:**
MySQL 8.0.16+ enforces `CHECK` constraints, but they cannot call user-defined
functions. If the source PostgreSQL extension validates data via CHECK
constraint functions, that mechanism doesn't exist in MySQL. Validate in the
store/parse function instead, and document it.

**DEFAULT expressions cannot call UDFs:**
MySQL 8.0.13+ supports `DEFAULT (expression)`, but the expression cannot
call user-defined functions. If the source extension provides defaults via
function calls (e.g. `DEFAULT my_generate_id()`), the MySQL port must use
a trigger or application-level default. Document this.

**Trigger functions:**
PostgreSQL trigger functions return `trigger` and can contain arbitrary
logic. MySQL triggers are SQL-only — you cannot delegate a trigger to an
extension function. If the source extension provides trigger functions, the
MySQL port must provide SQL trigger templates that call the extension
functions explicitly. Document the trigger pattern in the README.

**Expression-based indexes require deterministic functions:**
MySQL 8.0+ supports `CREATE INDEX idx ON t ((my_func(col)))` but the
function must be deterministic (no random, time, session variables). If the
source PostgreSQL extension marks functions `IMMUTABLE`, those are candidates
for expression indexes — document which functions qualify and which do not.
Non-deterministic functions cannot be indexed; say so explicitly.

**Float precision:**
MySQL `FLOAT` is single-precision (32-bit, ~7 significant digits). If the
source extension uses PostgreSQL `real` for values requiring more precision,
use `DOUBLE` instead. The type mapping table maps `float4` → `FLOAT` as a
starting point, but override this if the domain requires it.

**Thread safety:**
VEF extensions run in the context of the calling connection thread. MySQL is
multi-threaded — if the extension caches any global state, it must be
thread-safe (mutex or connection-local storage). PostgreSQL's process-per-
connection model means global state in a PG extension is implicitly safe.
Audit the source extension for global/static variables before porting.

**Connection-local state:**
If the source extension maintains per-session state, verify during Phase 2
bootstrap whether VEF exposes connection handle APIs for storing it. If not,
document the gap in `limitations.md`.

**Memory limits:**
MySQL `max_allowed_packet` limits the size of packets including function
inputs and outputs. The default is 64MB. If the extension processes large
inputs (large JSON documents, long strings, binary blobs), test at typical
data sizes and document any effective limit. Large inputs that exceed the
packet limit will produce a protocol error, not a function-level NULL.

**JSON path syntax:**
MySQL JSON path syntax (`$.key`, `$[0]`, `$.**.key`) differs from
PostgreSQL's `jsonpath` syntax. If the source extension accepts path
expressions as strings, the MySQL port must either translate them or define
its own path syntax and document the difference.

**Catalog access:**
If the source extension queries PostgreSQL system catalogs
(`pg_catalog`, `pg_class`, etc.), that is not available in MySQL extensions.
MySQL's `INFORMATION_SCHEMA` and `performance_schema` are accessible via SQL
but not from extension C++ code. Mark these functions Blocked and document
what the caller must do instead.

**Sorting and optimization:**
MySQL cannot use function immutability to optimize `ORDER BY my_func(col)`.
Every call recalculates. If the source extension relies on index scans via
immutable functions for performance, the MySQL port will be slower on large
tables. Suggest generated columns as an alternative for frequently-sorted
computed values.

## What to Put in the README for PostgreSQL Users

Add a **"Migrating from PostgreSQL"** section to README.md. Structure it as:

1. **Function name mapping table** — two columns: PostgreSQL name on the
   left, VillageSQL name on the right. Every renamed function. Make it
   scannable, not prose.

2. **Operator equivalents** — explicit table: PG operator on the left,
   VillageSQL function call on the right, with a one-line example for each.
   Do not just say "operators are not available" — show the replacement.

3. **Before and after examples** — for the most common use cases, show
   actual SQL: the PostgreSQL version and the VillageSQL equivalent
   side-by-side. Examples are worth more than any amount of prose description.

4. **Behavioral differences** — cover: NULL handling, error behavior, type
   differences (especially BOOLEAN, TIMESTAMP timezone loss, interval units),
   case sensitivity of key lookups, SRF workaround format and ordering,
   strict mode implications, and any function that returns a different type
   than its PostgreSQL counterpart.

5. **Missing functions** — list every Blocked function from the function map.
   For each: one line on why it isn't available, and what the closest
   workaround is. Do not omit this section even if the list is short — users
   will try to call these functions and need to know.

6. **Performance notes** — if the port uses JSON arrays instead of SRFs, or
   if the type mapping changes storage characteristics, note any performance
   implications. PostgreSQL users may have performance expectations from the
   original extension.

This section is the primary migration aid. Write it after Phase 5 UAT so the
examples are verified against the live server.
