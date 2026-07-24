---
name: repo-conventions
description: Repository-specific conventions and hard-won lessons for uc-local-apex-dev — shell script hygiene, Oracle/container runtime gotchas, image-source/registry behavior, and the Astro/Starlight docs site. Use before editing scripts, container/compose config, or docs to avoid known pitfalls.
---

# uc-local-apex-dev — Repository Conventions & Gotchas

This is a shared-knowledge file for anyone (human or AI agent) making changes in this repository. It
collects conventions and lessons learned that are easy to re-break if you don't know about them. Read the
relevant section before touching the area it covers.

## Shell scripts (`scripts/**/*.sh`, `install.sh`, `setup.sh`, `local-26ai.sh`)

- **Line endings must be LF, not CRLF.** `.gitattributes` declares `*.sh text eol=lf`, and `install-git-hooks`
  installs a pre-commit hook that checks this. A script with CRLF line endings fails at execution time with
  `/usr/bin/env: 'bash\r': No such file or directory` (the kernel's shebang parser chokes on the `\r`). If a
  script was created/edited with a tool that reintroduces CRLF, run `sed -i 's/\r$//' path/to/script.sh`
  before committing. Run `./local-26ai.sh install-git-hooks` once per clone to get this checked automatically.
- **Never edit a `.sh` file while it (or a script that sources it) is still executing in a foreground/background
  process**, even if execution has already passed the lines you're changing. Bash tracks a byte-offset read
  position into a running script file; inserting/removing lines shifts every later byte offset, so the
  interpreter's next read can land mid-line and throw a spurious `syntax error near unexpected token`
  that has nothing to do with the actual (valid) saved content. Wait for the process to exit, or edit a copy.
- **`set -euo pipefail` + referencing `.env` variables requires actually sourcing `.env`**, not just
  grep-validating that the expected keys are present. `install.sh` once validated key presence but never
  exported the values into its own shell, causing `ORACLE_PASSWORD: unbound variable` later in the script.
  The fix pattern used throughout this repo: `set -a; source <(tr -d '\r' <.env); set +a` (the `tr -d '\r'`
  guards against a CRLF `.env` file too).
- Every script that prints itself in `local-26ai.sh --help` needs a `# desc: <one-line description>` comment
  as its second line (see any existing script for the pattern) — `local-26ai.sh`'s `print_command()` greps
  for this exact line.
- New top-level scripts must be (a) added to the relevant `for cmd in ...` loop in `local-26ai.sh`'s
  `print_help()`, and (b) added to the [Command Reference](../../../docs/src/content/docs/reference/commands.mdx)
  doc page — these two lists drift independently and both need updating.

## Oracle / container runtime gotchas

- **Orphaned Oracle background processes survive `podman rm -f` / `docker rm -f`** in rootless
  Podman setups (and can happen with Docker too). Symptom: a freshly (re)started container gets stuck with
  `ORA-01102: cannot mount database in EXCLUSIVE mode`, `ORA-09968`/`ORA-27086` (lock file already held), or
  the DB reaches `STATUS=STARTED` but never `OPEN` (`ORA-01507: database not mounted`) — cascading into ORDS
  returning HTTP 571 "DatabaseConnectionError" / `ORA-12514`. Root cause: killing the container does not
  always reliably kill its `ora_*`/`tnslsnr` processes; they become orphaned on the host and keep OS-level
  file locks on the same datafiles/controlfile in the (shared, persistent) data volume. Diagnose with
  `ps -eo pid,lstart,cmd | grep -iE 'ora_pmon|ora_smon|tnslsnr'` — a process with a start time **older** than
  the current container's creation time is an orphan. Fix: kill the specific orphaned PIDs (or, if unsure,
  `pkill -9 -f '_POD1'; pkill -9 -f 'tnslsnr'`) before restarting. Prefer a graceful `stop` (SIGTERM, lets the
  DB shut down cleanly) over `rm -f` (SIGKILL) when you just want to restart/iterate, to avoid creating this
  problem in the first place.
- **`pkill -f`/`pgrep -f` self-match inside `container exec ... bash -c '<script containing the same pattern>'`**:
  if the pattern you're killing on (e.g. `"ords.war"`) also appears as literal text in the `bash -c` argument
  string that invoked the kill itself, the invoking process can match its own pattern and get killed first —
  combined with `set -euo pipefail`, this aborts the whole wrapper script silently with no obvious error at
  the failure point. Fix: break the literal self-match while keeping the same regex match, e.g.
  `pkill -f "[o]rds.war"` instead of `pkill -f "ords.war"`.
- **Nested-shell SQL quoting**: piping SQL through several nested shells (host → `exec bash -c '...'` →
  `sqlplus`/`sql`) makes escaping `$` in identifiers like `v$pdbs`/`v$instance` extremely fragile. Prefer
  writing the SQL to a local file/heredoc, copying it into the container, then running
  `sqlplus -s / as sysdba < /path/to/file.sql` — avoids nested-quoting entirely.
- **Self-signed certificate CN/SAN must actually match the hostname you connect to.** A cert whose `CN` is
  the container's internal hostname (not `localhost`) can trigger a browser's stricter
  "scrambled/incorrect credentials" error instead of the normal dismissable self-signed warning. This repo's
  `scripts/create-self-signed-certificates.sh` generates a cert for `localhost`/`127.0.0.1`/`::1` — keep it
  that way if you touch it. It prefers `openssl` and falls back to `mkcert` (no `sudo` required either way);
  on WSL it also imports the certificate into the Windows user certificate trust store automatically.
- Running `exec` into a container immediately after rapid stop/rm/recreate cycles can intermittently fail
  with runtime errors unrelated to the container's actual health (e.g. `crun: container ... does not exist`)
  — don't loop-retry more than a couple of times; fall back to log-based diagnosis (`logs`) instead.

## Image sources / registries (`switch-image-source.sh`, `install-registry-ca.sh`, `IMAGE_SOURCE`)

- Standard Docker/Podman/OCI clients always ping the bare `https://<host>[:port]/v2/` first, regardless of
  any path in the image reference — the repository path is only used in later `/v2/<name>/...` calls, never
  in the initial ping. If a company registry mirror is configured with an Artifactory-style **path-based**
  Docker method, that bare ping returns something like `{"errors":[{"status":400,"message":"Unsupported v2
  repository request for ''"}]}` — this looks like an auth or typo problem but is really a fundamental
  incompatibility with path-based Docker repos. Fix: use the registry's **subdomain method** instead (the
  repo/project key becomes part of the hostname, e.g. `<repo-key>.<registry-host>`) so the bare `/v2/` ping
  hits the right virtual host and returns a normal `401 Unauthorized` instead of a routing error.
- A company/internal registry's CA certificate lives in a *separate* trust store from the system/curl CA
  bundle when using Podman — `install-registry-ca.sh` installs it under
  `/etc/containers/certs.d/<host>/ca.crt` inside the Podman machine, which only Podman/skopeo's own registry
  client honors. Plain `curl` (without `-k`) will still report "unable to get local issuer certificate" for
  that host even after this — that's expected, not a sign the CA install failed.
- Keep real internal registry hostnames, proxy hosts/ports, PAC URLs, and IP addresses **out of this public
  repository**. Existing scripts already accept a generic `company` profile as a placeholder concept — if you
  need to document a specific organization's real values, follow the sanitized-template pattern in
  [`docs/src/content/docs/getting-started/enterprise-mirror-template.md`](../../../docs/src/content/docs/getting-started/enterprise-mirror-template.md)
  and keep the real values in a private wiki/repo, not here.

## Docs site (`docs/`, Astro + Starlight)

- The sidebar in `docs/astro.config.mjs` is **explicit arrays per section**, not autogenerated (except the
  "Migrations" section, which uses `{ autogenerate: { directory: "migrations" } }`). A page's frontmatter
  `sidebar: { order: N }` has **no effect on nav order or Prev/Next pagination** for explicit sections — only
  editing the `items` array changes that. It's easy to add a new doc page under
  `docs/src/content/docs/**` and forget to also add it to `astro.config.mjs`'s `sidebar` array, leaving it an
  orphan page reachable only via direct links.
- Mermaid diagrams are supported via the `astro-mermaid` integration (registered **before** `starlight()` in
  `integrations`) — use plain ` ```mermaid ` fenced code blocks in `.md`/`.mdx` files, no import needed.
- Starlight's directive-style asides (`:::note[Title]`, `:::tip[...]`, `:::caution[...]`) work in plain
  `.md` files without any component import; use `<Aside type="..." title="...">` (imported from
  `@astrojs/starlight/components`) only when you need finer control.
- Heading anchors are generated by lowercasing, stripping punctuation (`:`, `,`, `'`, `+`, etc.), and turning
  spaces into hyphens — text with punctuation removed next to a space can produce a **double hyphen** (e.g.
  "ADB Free vs DB + ORDS Stack" → `#adb-free-vs-db--ords-stack`). Double-check generated anchors when linking
  across doc pages instead of guessing.
- `starlightLinksValidator` is configured with `errorOnLocalLinks: false`, so a broken internal link only
  warns at build time, it does not fail the build — don't rely on the build to catch every broken link;
  check manually.
- Real company-specific values (internal tool names, AD/IAM group names, internal URLs) should not be added
  to public doc pages — follow the same sanitized-placeholder pattern used in
  `enterprise-mirror-template.md` and the Onboarding/Architecture docs.

## Before opening a PR / making a batch of changes

1. If you touched any `.sh` file, verify LF line endings and run `./local-26ai.sh install-git-hooks` once so
   the pre-commit hook catches this going forward.
2. If you added/renamed a script command, update both `local-26ai.sh`'s `print_help()` and
   `docs/src/content/docs/reference/commands.mdx`.
3. If you added a new doc page, add it to `docs/astro.config.mjs`'s `sidebar` array, and link to it from at
   least one existing related page.
4. If you changed container/compose behavior (ports, volumes, env vars), check whether
   `docs/src/content/docs/reference/architecture.md` needs a matching update — it documents exact
   container/port/volume facts and will silently go stale otherwise.
5. Never commit real secrets, internal hostnames/IPs, or proxy details — `.env`/`.env.adb`/`.certs/` etc. are
   already gitignored; keep it that way, and keep new documentation generic per the sanitized-template
   pattern above.
