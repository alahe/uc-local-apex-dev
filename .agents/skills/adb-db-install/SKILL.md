---
name: adb-db-install
description: Install Oracle database schemas from SQLcl snapshot exports into an ADB Free container. Handles schema creation, object installation order, cross-schema grants, and ADB-specific limitations.
---

# ADB Database Installation Skill

Install Oracle database objects from a SQLcl Liquibase/snapshot export directory into an ADB Free container.

## When to Use

- Installing database schemas from a Git repository into ADB Free
- Migrating on-premises Oracle database code to ADB Free
- Setting up development environments with existing database structures

## Step-by-Step Guide: Downloading & Installing DB Code

To download and install the database components from a Git repository (like `alis`, or in the future any other application like `argus`):

### 1. Download/Clone the Database Repository
Clone the source database repository to a folder next to your `uc-local-apex-dev` workspace (e.g., inside `~/Oracle/`):

```bash
# Example for ALIS:
cd ~/Oracle
git clone https://github.com/alahe/alis.git

# Example for a future application (like ARGUS):
# git clone https://github.com/alahe/argus.git
```

### 2. Identify the Database Source Directory
Verify the path to the database source files. It should contain folders named after the database schemas:
- For ALIS: `/Users/allanlahe/Oracle/alis/src/database`
- For a future app: `/Users/allanlahe/Oracle/argus/src/database`

### 3. Run the Automated Installer
Run the installer skript inside your local APEX orchestration workspace, passing the path to the database source directory:

```bash
# Run full installation:
./scripts/alis/install.sh /Users/allanlahe/Oracle/alis/src/database

# Run only post-install modifications (such as FK constraints & grants recompilation):
./scripts/alis/install.sh /Users/allanlahe/Oracle/alis/src/database --post
```

---

## Automated SQL Modifications on the Fly

The installer script contains a helper function `prepare_sql_file` which dynamically prepares and cleans the SQL files before copying them to the container. This prevents syntax errors and schema contamination without modifying your clean git checkout of the application.

### 1. Removing CTE Schema Prefixes
- **What it does**: Searches SQL files for schema-prefixed Common Table Expressions (e.g. `hcl.doc_select`) and removes the schema prefix (replacing it with `doc_select`).
- **Why it is needed**: In Oracle, CTEs defined in `WITH` clauses are local query blocks and do not belong to a schema. Schema-prefixing them (a common bug in snapshot exporters) causes `ORA-00942: table or view does not exist` errors, which in turn invalidates package bodies and causes secondary compiler errors (`PLS-00364: loop index variable use is invalid`).

---

## ADB Free Key Differences

### No SYSDBA Access
ADB Free does not allow `/ AS SYSDBA` connections from outside. Use `ADMIN` user instead — it has near-DBA privileges (287+ system privileges including `CREATE USER`, `CREATE ANY TABLE`, `GRANT ANY ROLE`, etc.).

### ADMIN Schema Conflict
ADB Free's `ADMIN` user is the main privileged user. If your source database also has an `ADMIN` schema with its own objects:
- **Option A**: Install ADMIN objects directly into ADB's ADMIN schema (they share the namespace)
- **Option B**: Rename the schema (e.g., `APP_ADMIN`) and update all references
- **Recommended**: Option A — ADB's ADMIN schema is empty by default, so your objects won't conflict

### Connection Details
- **Inside container**: `sql admin/<password>@localhost:1521/<SERVICE_NAME>`
- **Container exec**: `docker exec local-adb-free bash -c 'sql -s ...'`
- **Service name**: Configured in `.env.adb`, default `MYATP`
- **mTLS port 1522**: Requires wallet, avoid for install scripts
- **TLS port 1521**: Works inside container without wallet

### SYS Grants
In ADB Free, `ADMIN` can execute most `GRANT ... ON SYS.<object>` statements. Some may fail:
- `GRANT ALTER ON SYS.AUD$` — likely restricted
- `GRANT EXECUTE ON SYS.DBMS_PIPE` — may be restricted  
- `GRANT EXECUTE ON SYS.DBMS_SYS_SQL` — may be restricted

**Strategy**: Run SYS grants with `WHENEVER SQLERROR CONTINUE` and log failures for manual review.

## SQLcl Snapshot Export Structure

```
src/database/
├── <schema_name>/
│   ├── tables/           # CREATE TABLE statements
│   ├── indexes/          # CREATE INDEX statements  
│   ├── sequences/        # CREATE SEQUENCE statements
│   ├── views/            # CREATE VIEW statements
│   ├── materialized_views/
│   ├── materialized_view_logs/
│   ├── synonyms/         # CREATE SYNONYM
│   ├── type_specs/       # CREATE TYPE
│   ├── functions/        # CREATE FUNCTION
│   ├── procedures/       # CREATE PROCEDURE
│   ├── package_specs/    # CREATE PACKAGE
│   ├── package_bodies/   # CREATE PACKAGE BODY
│   ├── triggers/         # CREATE TRIGGER
│   ├── ref_constraints/  # ALTER TABLE ADD CONSTRAINT (FK)
│   ├── comments/         # COMMENT ON TABLE/COLUMN
│   ├── object_grants/    # GRANT statements
│   ├── aq_queue_tables/  # AQ queue tables
│   ├── aq_queues/        # AQ queues
│   └── jobs/             # DBMS_SCHEDULER jobs
├── sys/
│   └── object_grants/    # SYS-level grants (run as ADMIN)
└── public/
    └── synonyms/         # Public synonyms (run as ADMIN)
```

Each `.sql` file contains a DDL statement + a `-- sqlcl_snapshot {...}` comment.

## Installation Order

### Phase 1: SYS Grants (as ADMIN)
Run `sys/object_grants/*.sql` as ADMIN — these grant access to SYS packages.

### Phase 2: Create Schemas
Create user schemas with passwords. Skip `sys`, `public`, and `admin` (already exists in ADB).

```sql
CREATE USER <schema> IDENTIFIED BY <password>;
GRANT CONNECT, RESOURCE TO <schema>;
ALTER USER <schema> QUOTA UNLIMITED ON DATA;
```

### Phase 3: Install Objects (per schema, in order)
For each schema, run files in this order:

1. `tables/` — base tables
2. `sequences/`
3. `type_specs/`
4. `indexes/`
5. `comments/`
6. `views/`
7. `materialized_view_logs/`
8. `materialized_views/`
9. `synonyms/`
10. `aq_queue_tables/`
11. `aq_queues/`
12. `functions/`
13. `procedures/`
14. `package_specs/`
15. `package_bodies/`
16. `triggers/`
17. `jobs/`

### Phase 4: Cross-Schema References
After ALL schemas are created:
1. `ref_constraints/` — foreign keys (may reference other schemas)
2. `object_grants/` — cross-schema grants
3. `public/synonyms/` — public synonyms

### Phase 5: Recompile
```sql
EXEC DBMS_UTILITY.compile_schema('<SCHEMA>', compile_all => FALSE);
```

## SQL Execution Pattern

Each SQL file should be run in the context of its schema:

```sql
ALTER SESSION SET CURRENT_SCHEMA = <schema>;
@/path/to/file.sql
```

Or connected directly as ADMIN with `CREATE ANY TABLE` etc. privileges.

> [!WARNING]
> **Accidental ADMIN Schema Creation**: When executing manual DDL (like `CREATE OR REPLACE PACKAGE`) while logged in as `ADMIN`:
> - `ALTER SESSION SET CURRENT_SCHEMA = <schema>;` only affects table/view name resolution.
> - It **does NOT** change the target schema of a `CREATE` statement. Objects created without an explicit schema prefix will default to the current login user (`ADMIN`).
> - Always ensure the DDL contains the schema prefix: `CREATE OR REPLACE PACKAGE <schema_name>.<package_name>`.

**Error handling**: Use `WHENEVER SQLERROR CONTINUE` during installation, collect errors, and report at the end.

## Adapting SQL Files for ADB

Some statements may need modification:

| Issue | Solution |
|-------|----------|
| `TABLESPACE <name>` | Remove or replace with `DATA` |
| `STORAGE (...)` clauses | Remove (ADB manages storage) |
| `ORGANIZATION INDEX` | Usually works, but verify |
| `DBMS_PIPE`, `UTL_FILE` | May be restricted in ADB |
| Schema-prefixed DDL (`CREATE TABLE admin.xxx`) | Works if run as ADMIN |

## References

- ADB Free container: `ghcr.io/oracle/adb-free:latest-26ai`
- ADMIN privileges: 287 system privileges (near-DBA)
- Default tablespace: `DATA`
- Connection from inside container: `localhost:1521/<SERVICE>`

## Known Issues & Workarounds

### 1. CTE Schema Prefix in PL/SQL (ORA-00942 / PLS-00364)
- **File**: `hcl/package_bodies/doc_document_gen.sql` (Line 276)
- **Problem**: The snapshot exporter prefixed a Common Table Expression (CTE) with the schema name: `hcl.doc_select dd2`. Since CTEs are local query blocks and do not have a schema, this causes a compilation error.
- **Symptom**: Package fails to compile with `ORA-00942` and `PLS-00364` (loop index variable `C_REC1` use is invalid).
- **Fix**: Remove the schema prefix. Change `hcl.doc_select dd2` to `doc_select dd2`.

### 2. Custom Type Dependency (ORA-00902)
- **Problem**: Tables using custom database types fail to create with `ORA-00902: invalid datatype` if `tables` are loaded before `type_specs`.
- **Fix**: The `install.sh` order starts with `type_specs` before `tables` to resolve all database-level type dependencies.
