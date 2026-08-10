---
name: vsql-install-server
description: >
  Get a working VillageSQL server on this machine and prove it works —
  choose an install path (installer, Docker, or source), start the server,
  connect, load a bundled extension, and call one of its functions. Also
  covers reconnecting to a server that is already running. Use before
  vsql-extension-builder, or any time a VillageSQL server is needed and
  none is confirmed working.
---

# VillageSQL Server Install and Verify

Do not skip to installing. A server is often already running, and a second
one on port 3306 will fail to start.

## Arguments

If invoked as `/vsql-install-server <path>` where `<path>` is `installer`,
`docker`, or `source`, skip Step 1 and use that path.

## Step 0 — Is a server already running?

```bash
pgrep -l mysqld
```

If a PID comes back, read its actual arguments rather than assuming the
defaults. On macOS `pgrep -a` does not print arguments; use `ps`:

```bash
ps -o command= -p <PID>
```

Take the `--socket` and `--port` values from that output and use them for
every later connection. Do not assume `/tmp/mysql.sock`. A machine can have
a source build, an installer build, and a Homebrew MySQL all present, and
the socket is the only reliable way to reach the one that is actually up.

Confirm which server you reached before doing anything else:

```bash
mysql -u root --socket=<socket-from-ps> -e "SELECT VERSION();"
```

A VillageSQL server reports a version like `8.4.10-villagesql-0.0.6`. If the
version has no `villagesql` in it, you have reached a stock MySQL and should
stop it or pick a different port before continuing.

If a working VillageSQL server is already up, skip to Step 4.

## Step 1 — Choose an install path

| Path | Use when | Gets you |
|---|---|---|
| **Installer** | Default choice. You want to use VillageSQL, or build and test extensions. | Server, client, extension SDK, MTR test runner |
| **Docker** | You want a disposable server, or you are on a machine you do not want to install onto. | Server, client, extension SDK, C++ toolchain. **No MTR test runner.** |
| **Source** | You are changing the server itself. | Everything, plus the server build tree |

The Docker limitation is specific and worth stating plainly to the user
before they pick it: you can build an extension and verify it by hand over
SQL inside the container, but you cannot run its MTR test suite there,
because the image is built with `-DINSTALL_MYSQLTESTDIR=""` and excludes the
test suites. If the goal is the full `vsql-extension-builder` workflow,
recommend the installer.

## Step 2 — Install

### Installer

```bash
curl -fsSL https://install.villagesql.com | bash
```

This writes `~/.villagesql/credentials.txt`. Read it — do not guess paths.
It records the install dir, build dir, data dir, port, socket, log path, the
generated root password, and the exact start, connect, and stop commands for
this machine. It also notes the `villagesql` and `villagesql-server`
shortcuts the installer adds.

```bash
cat ~/.villagesql/credentials.txt
```

The file contains a password. Do not echo it into a shared transcript, a
commit, or a bug report.

### Docker

```bash
docker run -d --name vsql \
  -e MYSQL_ALLOW_EMPTY_PASSWORD=yes \
  -p 3306:3306 \
  villagesql/server:stable
```

Drop `-p 3306:3306` if something already holds 3306 on the host and you
intend to work inside the container with `docker exec`.

The image uses the standard MySQL entrypoint environment variables:
`MYSQL_ROOT_PASSWORD`, `MYSQL_ALLOW_EMPTY_PASSWORD`,
`MYSQL_RANDOM_ROOT_PASSWORD`, `MYSQL_DATABASE`, `MYSQL_USER`,
`MYSQL_PASSWORD`. Exactly one of the three root-password variables is
required or the container refuses to initialize.

### Source

Follow the server repo build instructions. Build the server before any
extension — extensions need the SDK that the server build produces.

## Step 3 — Start the server

For an installer or source install, use the exact command
`credentials.txt` prints for this machine rather than composing one. It looks
like this:

```bash
mysqld --datadir=<data-dir> --socket=<socket> --port=<port> --daemonize
```

One thing that reliably bites: never write `--datadir=~/...`. No shell
expands `~` after `=`, so mysqld receives a literal `~` and aborts. Use
`$HOME` or an absolute path.

`vsql_allow_preview_extensions` defaults to `OFF`. Add
`--vsql_allow_preview_extensions=ON` at startup only if you need an
extension that declares a preview capability. It cannot be turned on later
with `SET GLOBAL`.

A Docker container started with `-d` is already running. Wait for readiness
rather than sleeping a fixed amount:

```bash
until docker exec vsql mysqladmin ping --silent 2>/dev/null; do sleep 2; done
```

## Step 4 — Connect and confirm the build

```bash
mysql -u root --socket=<socket> -e "SELECT VERSION();"
```

In Docker:

```bash
docker exec vsql mysql -u root -e "SELECT VERSION();"
```

Report the version string back to the user. This is the one fact that
everything downstream depends on.

## Step 5 — Load an extension and call it

Shipping a server is not the same as having a working extension pipeline.
Prove the pipeline with a bundled extension.

Several extensions ship pre-built with the installer, the Docker image, and
the release tarballs, so there is nothing to download. Do not hardcode the
list or the directory — ask the server where it looks:

```sql
SHOW VARIABLES LIKE 'veb_dir';
```

Then list that directory. It is `/usr/lib/veb/` in the Docker image and
`<build-or-install-dir>/lib/veb/` for a source or installer build.

A hand-rolled source build is the exception: it produces no bundled `.veb`
files, so that directory can legitimately be empty.

Shipping the `.veb` is not the same as installing the extension. Install it:

```sql
INSTALL EXTENSION vsql_uuid;
```

The extension name is a **bare SQL identifier**. Quoting it is a syntax
error:

```
ERROR 1064 (42000): You have an error in your SQL syntax; check the manual that
corresponds to your MySQL server version for the right syntax to use near
''vsql_uuid'' at line 1
```

A name containing hyphens needs backticks. `VERSION 'x.y.z'` is a string
literal and does keep its quotes.

Confirm it registered:

```sql
SELECT EXTENSION_NAME, EXTENSION_VERSION FROM INFORMATION_SCHEMA.EXTENSIONS;
```

The columns are `EXTENSION_NAME`, `EXTENSION_VERSION`, `PENDING_VERSION`,
`PENDING_REQUESTED_AT`, `PENDING_LAST_ERROR`, `PENDING_LAST_ERROR_AT`. Using
`NAME` or `VERSION` gives:

```
ERROR 1054 (42S22): Unknown column 'NAME' in 'field list'
```

Extension functions do **not** appear in `INFORMATION_SCHEMA.ROUTINES` —
that view stays empty for them. `INFORMATION_SCHEMA.EXTENSIONS` and
`INFORMATION_SCHEMA.EXTENSION_REGISTRATION` are the views that know about
them. `EXTENSION_REGISTRATION.REGISTRATION_JSON` lists every function the
extension registered, with return types, parameter types, and arity — read it
instead of guessing a function name:

```sql
SELECT REGISTRATION_JSON FROM INFORMATION_SCHEMA.EXTENSION_REGISTRATION
  WHERE EXTENSION_NAME = 'vsql_uuid';
```

Then call one. No database needs to be selected:

```sql
SELECT UUID_V4();
SELECT UUID_VERSION(UUID_V4());
```

Do not assume PostgreSQL-style names. `vsql_uuid` provides `UUID_V4()`, not
`uuid_generate_v4()`.

If the name does not resolve, the error depends on whether a database is
selected, and the no-database form is misleading — it reports a database
problem when the real problem is an unknown function:

```
ERROR 1046 (3D000): No database selected
ERROR 1305 (42000): FUNCTION demo.no_such_fn does not exist
```

So if you hit `ERROR 1046` on a function call, do not go hunting for a
database issue. Select any database and re-run to get the error that names
the function.

If the arity is wrong, the server says so exactly — check
`REGISTRATION_JSON` rather than guessing:

```
ERROR 3219 (HY000): Cannot initialize function '<name>': wrong number of arguments (expected 0, got 1)
```

Re-running an install that already succeeded is harmless and self-reporting:

```
ERROR 3219 (HY000): Extension '<name>' is already installed
```

## Step 6 — Building an extension in Docker

Only relevant if the user chose Docker and wants to build an extension.

The image ships the SDK at `/usr/include/villagesql/`, its CMake package at
`/usr/lib/cmake/VillageSQLExtensionFramework/`, a C++ toolchain, and a
helper script. Mount your extension source and build it:

```bash
docker run -d --name vsql -e MYSQL_ALLOW_EMPTY_PASSWORD=yes \
  -v /path/to/my-extension:/src:ro villagesql/server:stable

docker exec vsql bash -c 'cp -r /src /work && vsql-build-extension.sh /work'
```

The helper runs cmake and make, installs the resulting `.veb` into
`/usr/lib/veb/`, and waits for the server. Then `INSTALL EXTENSION` it as in
Step 5.

Mount read-only and copy to `/work` as shown. The helper builds into
`<source>/_docker_build`, which would otherwise write build output back into
your host checkout.

There is no MTR runner in this image. If the user needs the test suite, they
need an installer or source build.

## Step 7 — Report

Tell the user, in plain words:

- which install path was used, and where things live
- the `SELECT VERSION()` output
- which extension was installed and what the function call returned
- the exact connect command for this machine
- if Docker: that the MTR test phase is unavailable here

## Extensions, plugins, and components

VillageSQL is a drop-in MySQL replacement, so MySQL plugins and components
work as they do in MySQL, while VEF extensions are the model for adding new
functionality and the only one that can define custom column types. Do not
re-explain the comparison in your own words — point the user at
[Extensions or Plugins and Components](https://villagesql.com/docs/mysql-8.4/stable/extensions-or-plugins),
which exists for exactly this question.

## Common failures

| Symptom | Cause |
|---|---|
| Server will not start, port in use | Another MySQL on 3306. Stop it (`brew services stop mysql`, `systemctl stop mysql`) or pick another port. |
| mysqld aborts complaining about the data directory | `--datadir=~/...` passed a literal `~`. Use `$HOME` or an absolute path. |
| Connects, but version has no `villagesql` | You reached a stock MySQL. Re-check the socket from `ps`. |
| `ERROR 1064` on `INSTALL EXTENSION` | The extension name was quoted. It is a bare identifier. |
| `ERROR 3219 (HY000): VEB file not found: <name>.veb` | The `.veb` is not in the server's veb directory. Check `lib/veb/` (or `/usr/lib/veb/` in Docker) and confirm the spelling. |
| Rebuilt an extension, still see old behaviour | The old `.veb` is still what the server loads. `SHOW VARIABLES LIKE 'veb_dir'` to find the directory the server actually reads, and put the rebuilt file there — copying it into `lib/plugin` does nothing. Check `EXTENSION_VERSION` in `INFORMATION_SCHEMA.EXTENSIONS` to confirm which build is live, and install with an explicit `VERSION 'x.y.z'` so a stale `.veb` fails loudly instead of silently. |
| `ERROR 1046 (3D000): No database selected` on a function call | Misleading. The function name did not resolve and there was no default schema to name in the error. `USE` any database and re-run to get `ERROR 1305` naming the function. |
| Extension installed but its functions are missing from `INFORMATION_SCHEMA.ROUTINES` | Expected. VEF functions never appear there. Use `INFORMATION_SCHEMA.EXTENSION_REGISTRATION`. |
