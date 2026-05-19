# Environment & Commands

## Build workflow

```bash
export VillageSQL_BUILD_DIR=/path/to/villagesql/build
cd extension-name/
./build.sh                # Produces build/<extension_name>.veb
cd build && make install  # Copies .veb to VEB directory
mysql -u root -e "INSTALL EXTENSION <extension_name>;"
```

`build.sh` template: use the version already in the cloned template — it
is correct. Verify it has `set -euo pipefail`, reads `VillageSQL_BUILD_DIR`,
and runs `cmake` + `cmake --build`. If it differs from the template,
update it.

## Test suite layout

```
mysql-test/
├── suite.opt   # Optional suite-wide flags (e.g. --log-error-verbosity=3)
├── t/          # *.test files
└── r/          # *.result files (generated via --record)
```

The suite directory must be named `mysql-test/` to match all other
VillageSQL extensions. Never `test/`.

## Run MTR from `{build_dir}/mysql-test`

```bash
perl mysql-test-run.pl --suite=/path/to/extension-name/mysql-test
perl mysql-test-run.pl --suite=/path/to/extension-name/mysql-test --record
```

## Common mysqltest directives

```
--echo message
--error ER_WRONG_ARGUMENTS
--disable_warnings / --enable_warnings
--replace_result $MYSQLTEST_VARDIR MYSQLTEST_VARDIR
```

Always use fully-qualified function names: `SELECT vsql_foo.my_func(...)`.
Install at test top, uninstall at bottom (or use `suite.opt`).

## Outbound network calls in tests

```
--exec python3 -m http.server 18888 --directory $MYSQLTEST_VARDIR &>/tmp/test.log &
--exec sleep 1
SELECT vsql_webhook.webhook_call('http://127.0.0.1:18888/');
--exec kill $(lsof -ti:18888) 2>/dev/null || true
```

## Key paths

- Staged SDK: `{build_dir}/villagesql-extension-sdk-*/` (newest by mtime)
- SDK version: `{sdk_dir}/bin/villagesql_config --version`
- SDK headers: `{sdk_dir}/include/` and `{sdk_dir}/include-dev/` (typed
  API may live in either; check both — see Phase 2 bootstrap)
- mysql (dev build): `{build_dir}/runtime_output_directory/mysql`
- mysqld (dev build): `{build_dir}/runtime_output_directory/mysqld`
- VEB directory: query the server (`SHOW VARIABLES LIKE 'veb_dir'`) —
  that value is authoritative. Typical dev-build location is
  `{build_dir}/villagesql/lib/veb/` but production installs vary.

## DDL syntax for custom types

```sql
CREATE TABLE t (col vsql_hstore.hstore);
CREATE TABLE t (col vsql_tvector.tvector(128));              -- integer shorthand
CREATE TABLE t (col vsql_tvector.tvector('dimension=128'));  -- key=value string
```

Extension name must be the install name (e.g., `vsql_hstore`).

`CAST(... AS <custom_type>)` is **not** supported — custom types aren't
wired into MySQL's CAST grammar. To get a value of a custom type, insert
into a column of that type or call the type's constructor VDF directly.

## Useful commands

- Verify loaded: call one of its functions. There is no `SHOW EXTENSIONS`.
- Uninstall: `UNINSTALL EXTENSION <extension_name>;` — no `IF EXISTS`.
  Use `|| true` in shell. ERROR 3219 when uninstalling a not-installed
  extension is safe to ignore.
- Reinstall (shell): run `UNINSTALL` and `INSTALL` as separate `mysql -e`
  calls.
- Remove cache: `rm -rf <veb_dir>/_expanded/<extension_name>`
- VEB contents: `make show_veb` (from build dir)
- Symbols: `nm -gU <extension>.so | grep vef_register`
