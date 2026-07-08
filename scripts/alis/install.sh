#!/bin/bash
# =============================================================================
# ALIS Database Installer for ADB Free
# =============================================================================
# Installs all ALIS database schemas from SQLcl snapshot export into ADB Free.
#
# Usage: ./scripts/alis/install.sh <source_dir>
# Example: ./scripts/alis/install.sh /Users/allanlahe/Oracle/alis/src/database
#
# Requirements:
# - ADB Free container running (docker exec local-adb-free)
# - .env.adb with ADB_ADMIN_PASSWORD
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_DIR/logs/alis-install"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/install_${TIMESTAMP}.log"
ERROR_LOG="$LOG_DIR/errors_${TIMESTAMP}.log"
touch "$ERROR_LOG"

# Source .env.adb
if [ -f "$PROJECT_DIR/.env.adb" ]; then
  # shellcheck disable=SC1091
  . "$PROJECT_DIR/.env.adb"
else
  echo "ERROR: .env.adb not found. Start ADB Free first: ./local-26ai.sh adb/start"
  exit 1
fi

# Arguments
SOURCE_DIR="${1:-}"
if [ -z "$SOURCE_DIR" ] || [ ! -d "$SOURCE_DIR" ]; then
  echo "Usage: $0 <source_database_dir> [--post]"
  echo "Example: $0 /path/to/alis/src/database"
  exit 1
fi

ONLY_POST="false"
if [ "${2:-}" = "--post" ] || [ "${2:-}" = "post" ]; then
  ONLY_POST="true"
fi

CONTAINER="local-adb-free"
ADMIN_PWD="$ADB_ADMIN_PASSWORD"
SERVICE="MYATP"
# ADB requires 12+ char passwords
SCHEMA_PWD="Welcome12345!"

# Helper: uppercase a string (zsh/bash compatible)
to_upper() {
  echo "$1" | tr 'a-z' 'A-Z'
}

# Object types in installation order
INSTALL_ORDER="type_specs tables sequences indexes comments views materialized_view_logs materialized_views synonyms aq_queue_tables aq_queues functions procedures package_specs package_bodies triggers jobs"

# Post-install phases (after all schemas)
POST_INSTALL_ORDER="ref_constraints object_grants"

# Schemas that need CREATE USER (not admin/sys/public)
NEW_SCHEMAS="logger db_installer crebit hc_pp hcgweb hcgweblv hcl hcl_arch hcl_leas lis_interface lis_restful verp_lt"

# All schemas with objects to install (in dependency order)
ALL_SCHEMAS="logger db_installer admin crebit hc_pp hcl hcl_arch lis_interface"

# Schemas with only grants (no DDL objects)
GRANT_ONLY_SCHEMAS="hcgweb hcgweblv hcl_leas verp_lt"

# =============================================================================
# Helper functions
# =============================================================================

log() {
  local msg="[$(date '+%H:%M:%S')] $*"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE"
}

log_error() {
  local msg="[$(date '+%H:%M:%S')] ERROR: $*"
  echo "$msg" >&2
  echo "$msg" >> "$LOG_FILE"
  echo "$msg" >> "$ERROR_LOG"
}

run_sql() {
  local sql_text="$1"
  docker exec "$CONTAINER" bash -c "sql -s admin/${ADMIN_PWD}@localhost:1521/${SERVICE} <<'SQLEOF'
WHENEVER SQLERROR CONTINUE
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK ON
${sql_text}
SQLEOF" 2>&1
}

run_sql_file_as_schema() {
  local schema="$1"
  local file="$2"
  local filename
  filename=$(basename "$file")
  local schema_upper
  schema_upper=$(to_upper "$schema")

  # Copy file to container
  docker cp "$file" "${CONTAINER}:/tmp/install_sql.sql" 2>/dev/null

  # Run as ADMIN with current_schema set
  local result
  result=$(docker exec "$CONTAINER" bash -c "sql -s admin/${ADMIN_PWD}@localhost:1521/${SERVICE} <<'SQLEOF'
WHENEVER SQLERROR CONTINUE
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK ON
ALTER SESSION SET CURRENT_SCHEMA = ${schema_upper};
@/tmp/install_sql.sql
SQLEOF" 2>&1)

  if echo "$result" | grep "ORA-" | grep -v "ORA-00955" | grep -v "ORA-01430" | grep -v "ORA-02275" | grep -q "ORA-"; then
    local err_line
    err_line=$(echo "$result" | grep "ORA-" | head -1)
    if [ -n "$err_line" ]; then
      log_error "[${schema_upper}/${obj_type_current:-unknown}] $filename: $err_line"
    fi
  fi

  echo "$result"
}

count_files() {
  local dir="$1"
  if [ -d "$dir" ]; then
    find "$dir" -name "*.sql" | wc -l | tr -d ' '
  else
    echo "0"
  fi
}

# =============================================================================
# Phase 0: Pre-flight checks
# =============================================================================

log "=========================================="
log "ALIS Database Installer for ADB Free"
log "=========================================="
log "Source: $SOURCE_DIR"
log "Container: $CONTAINER"
log "Log: $LOG_FILE"
log "Errors: $ERROR_LOG"
log ""

# Check container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  log_error "Container $CONTAINER is not running. Start with: ./local-26ai.sh adb/start"
  exit 1
fi

# Test connection
log "Testing database connection..."
result=$(run_sql "SELECT 'CONNECTION_OK' FROM dual;")
if ! echo "$result" | grep -q "CONNECTION_OK"; then
  log_error "Cannot connect to database: $result"
  exit 1
fi
log "Connection OK"

# =============================================================================
# Phase 1: Create Schemas (BEFORE SYS grants)
# =============================================================================

if [ "$ONLY_POST" = "false" ]; then

log ""
log "========== Phase 1: Create Schemas =========="

for schema in $NEW_SCHEMAS; do
  schema_upper=$(to_upper "$schema")

  # Check if user already exists
  exists=$(run_sql "
    SET FEEDBACK OFF
    SET HEADING OFF
    SELECT username FROM dba_users WHERE username = '${schema_upper}';
  ")
  if echo "$exists" | grep -q "$schema_upper"; then
    log "Schema $schema_upper already exists, skipping creation"
    continue
  fi

  log "Creating schema: $schema_upper"
  result=$(run_sql "
    CREATE USER ${schema_upper} IDENTIFIED BY \"${SCHEMA_PWD}\" DEFAULT TABLESPACE DATA QUOTA UNLIMITED ON DATA;
    GRANT CONNECT, RESOURCE TO ${schema_upper};
    GRANT CREATE VIEW TO ${schema_upper};
    GRANT CREATE SYNONYM TO ${schema_upper};
    GRANT CREATE SEQUENCE TO ${schema_upper};
    GRANT CREATE PROCEDURE TO ${schema_upper};
    GRANT CREATE TRIGGER TO ${schema_upper};
    GRANT CREATE TYPE TO ${schema_upper};
    GRANT CREATE TABLE TO ${schema_upper};
    GRANT CREATE JOB TO ${schema_upper};
    GRANT CREATE MATERIALIZED VIEW TO ${schema_upper};
  ")

  if echo "$result" | grep -q "ORA-"; then
    log_error "Failed to create schema $schema_upper: $(echo "$result" | grep 'ORA-' | head -1)"
  else
    log "Created $schema_upper successfully"
  fi
done

# =============================================================================
# Phase 2: SYS Grants (AFTER schemas exist)
# =============================================================================

log ""
log "========== Phase 2: SYS Grants =========="

SYS_GRANTS_DIR="$SOURCE_DIR/sys/object_grants"
if [ -d "$SYS_GRANTS_DIR" ]; then
  total=$(count_files "$SYS_GRANTS_DIR")
  log "Processing $total SYS grant files..."

  ok=0
  fail=0
  skip_self=0

  for f in "$SYS_GRANTS_DIR"/*.sql; do
    [ -f "$f" ] || continue
    # Read the grant statement (first line)
    grant_stmt=$(head -1 "$f" | tr -d '\r')

    # Skip empty lines
    [ -z "$grant_stmt" ] && continue

    # Check if granting to ADMIN (self-grant in ADB)
    if echo "$grant_stmt" | grep -qi "to admin"; then
      skip_self=$((skip_self + 1))
      continue
    fi

    result=$(run_sql "$grant_stmt")
    if echo "$result" | grep -q "ORA-"; then
      fail=$((fail + 1))
      log_error "SYS grant failed: $grant_stmt -> $(echo "$result" | grep 'ORA-' | head -1)"
    else
      ok=$((ok + 1))
    fi
  done

  log "SYS grants done: $ok OK, $fail failed, $skip_self skipped (self-grant to ADMIN)"
else
  log "No SYS grants directory found"
fi

# =============================================================================
# Phase 3: Install Objects (per schema)
# =============================================================================

log ""
log "========== Phase 3: Install Objects =========="

for schema in $ALL_SCHEMAS; do
  schema_dir="$SOURCE_DIR/$schema"
  [ -d "$schema_dir" ] || continue
  schema_upper=$(to_upper "$schema")

  log ""
  log "--- Schema: ${schema_upper} ---"

  for obj_type in $INSTALL_ORDER; do
    type_dir="$schema_dir/$obj_type"
    [ -d "$type_dir" ] || continue

    file_count=$(count_files "$type_dir")
    [ "$file_count" -eq 0 ] && continue

    obj_type_current="$obj_type"
    log "  Installing $obj_type ($file_count files)..."

    ok=0
    fail=0

    for f in "$type_dir"/*.sql; do
      [ -f "$f" ] || continue

      result=$(run_sql_file_as_schema "$schema" "$f")
      if echo "$result" | grep -q "ORA-"; then
        fail=$((fail + 1))
      else
        ok=$((ok + 1))
      fi
    done

    log "  $obj_type: $ok OK, $fail errors"
  done
done

fi # ONLY_POST = false

# =============================================================================
# Phase 4: Post-install (FK constraints and grants for ALL schemas)
# =============================================================================

log ""
log "========== Phase 4: FK Constraints & Grants =========="

for schema in $ALL_SCHEMAS $GRANT_ONLY_SCHEMAS; do
  schema_dir="$SOURCE_DIR/$schema"
  [ -d "$schema_dir" ] || continue
  schema_upper=$(to_upper "$schema")

  for obj_type in $POST_INSTALL_ORDER; do
    type_dir="$schema_dir/$obj_type"
    [ -d "$type_dir" ] || continue

    file_count=$(count_files "$type_dir")
    [ "$file_count" -eq 0 ] && continue

    obj_type_current="$obj_type"
    log "  ${schema_upper}/$obj_type ($file_count files)..."

    # Concatenate all files into a single temp file
    temp_concat="/tmp/concat_${schema}_${obj_type}.sql"
    rm -f "$temp_concat" 2>/dev/null || true
    touch "$temp_concat"

    # Combine all SQL statements
    for f in "$type_dir"/*.sql; do
      [ -f "$f" ] || continue
      cat "$f" >> "$temp_concat"
      echo "" >> "$temp_concat" # ensure newline
    done

    result=$(run_sql_file_as_schema "$schema" "$temp_concat")
    rm -f "$temp_concat" 2>/dev/null || true

    # Count ORA- errors in output
    fail=$(echo "$result" | grep -c "ORA-" || true)
    ok=$((file_count - fail))
    if [ $ok -lt 0 ]; then ok=0; fi

    log "  ${schema_upper}/$obj_type: $ok OK, $fail errors"
  done
done

# =============================================================================
# Phase 5: Public Synonyms
# =============================================================================

log ""
log "========== Phase 5: Public Synonyms =========="

PUBLIC_SYN_DIR="$SOURCE_DIR/public/synonyms"
if [ -d "$PUBLIC_SYN_DIR" ]; then
  for f in "$PUBLIC_SYN_DIR"/*.sql; do
    [ -f "$f" ] || continue
    syn_stmt=$(head -1 "$f" | tr -d '\r')
    [ -z "$syn_stmt" ] && continue
    log "  $syn_stmt"
    result=$(run_sql "$syn_stmt")
    if echo "$result" | grep -q "ORA-"; then
      log_error "Public synonym failed: $syn_stmt"
    fi
  done
else
  log "No public synonyms found"
fi

# =============================================================================
# Phase 6: Recompile
# =============================================================================

log ""
log "========== Phase 6: Recompile Invalid Objects =========="

for schema in $ALL_SCHEMAS; do
  schema_upper=$(to_upper "$schema")
  log "  Recompiling $schema_upper..."
  run_sql "EXEC DBMS_UTILITY.compile_schema('${schema_upper}', compile_all => FALSE);" > /dev/null 2>&1 || true
done

# =============================================================================
# Phase 7: Summary
# =============================================================================

log ""
log "========== Installation Summary =========="

# Build IN-list for query
in_list=""
for schema in $ALL_SCHEMAS $GRANT_ONLY_SCHEMAS; do
  schema_upper=$(to_upper "$schema")
  if [ -z "$in_list" ]; then
    in_list="'${schema_upper}'"
  else
    in_list="${in_list},'${schema_upper}'"
  fi
done

summary=$(run_sql "
SET PAGESIZE 200
SET LINESIZE 120
COLUMN owner FORMAT A20
COLUMN object_type FORMAT A25
COLUMN cnt FORMAT 9999
COLUMN invalid FORMAT 9999
SELECT owner, object_type, COUNT(*) AS cnt, SUM(CASE WHEN status = 'INVALID' THEN 1 ELSE 0 END) AS invalid
FROM dba_objects
WHERE owner IN (${in_list})
GROUP BY owner, object_type
ORDER BY owner, object_type;
")

log "$summary"

error_count=$(wc -l < "$ERROR_LOG" | tr -d ' ')

log ""
log "=========================================="
log "Installation complete!"
log "Total errors: $error_count"
log "Error log: $ERROR_LOG"
log "Full log: $LOG_FILE"
log "=========================================="
