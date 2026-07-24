#!/usr/bin/env bash
#
# Apply APEX Patch Set Bundles (PSBs) from the apex-patches/ directory.
#
# Usage:
#   ./local-26ai.sh apply-patches
#   ./scripts/apply-patches.sh          # direct
#
# The script:
#   1. Scans apex-patches/ for .zip files
#   2. Extracts patch numbers from filenames (p<NUMBER>_...)
#   3. Queries apex_patches to find already-installed patches
#   4. Installs missing patches in ascending order (by patch number)
#   5. Copies updated images to apex-images/
#   6. Shows a summary
#
# ORDS is NOT restarted by this script — the caller (install.sh or the user)
# is responsible for restarting ORDS after patching.

set -euo pipefail

source ./scripts/util/load_env.sh

PATCH_DIR="./apex-patches"

# ---------------------------------------------------------------------------
# Optional: fetch patch bundles from an internal mirror first
# ---------------------------------------------------------------------------
# Set APEX_PATCHES_MIRROR_URL (base URL of an internal artifact repository
# folder, no trailing slash) and APEX_PATCHES_MANIFEST (comma-separated list
# of the exact filenames uploaded there, e.g.
# "p39179920_2610_Generic.zip,p39355255_2610_Generic.zip") in .env to have
# missing patch bundles fetched automatically instead of everyone downloading
# them from My Oracle Support by hand. Any file already present locally is
# left untouched. Both variables are optional — leave unset to keep the
# existing manual "drop the zip in apex-patches/" workflow.
if [ -n "${APEX_PATCHES_MIRROR_URL:-}" ] && [ -n "${APEX_PATCHES_MANIFEST:-}" ]; then
  mkdir -p "$PATCH_DIR"
  IFS=',' read -ra MANIFEST_FILES <<<"$APEX_PATCHES_MANIFEST"
  for fname in "${MANIFEST_FILES[@]}"; do
    fname=$(echo "$fname" | xargs) # trim whitespace
    [ -z "$fname" ] && continue
    dest="$PATCH_DIR/$fname"
    if [ -f "$dest" ]; then
      continue
    fi
    echo "Fetching $fname from internal mirror..."
    if command -v curl >/dev/null 2>&1; then
      curl -fLo "$dest" "$APEX_PATCHES_MIRROR_URL/$fname" || echo "  WARNING: failed to fetch $fname from mirror" >&2
    elif command -v wget >/dev/null 2>&1; then
      wget -O "$dest" "$APEX_PATCHES_MIRROR_URL/$fname" || echo "  WARNING: failed to fetch $fname from mirror" >&2
    fi
  done
fi

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
if [ ! -d "$PATCH_DIR" ]; then
  echo "No $PATCH_DIR directory found — nothing to do."
  exit 0
fi

# Collect ZIP files
shopt -s nullglob
ZIP_FILES=("$PATCH_DIR"/*.zip)
shopt -u nullglob

if [ ${#ZIP_FILES[@]} -eq 0 ]; then
  echo "No .zip files in $PATCH_DIR — nothing to do."
  exit 0
fi

echo "Scanning $PATCH_DIR for APEX patch bundles..."
echo "Found ${#ZIP_FILES[@]} ZIP file(s)"

# ---------------------------------------------------------------------------
# Extract patch numbers from filenames
# ---------------------------------------------------------------------------
# Parallel arrays: PATCH_NUMS[i] <-> PATCH_ZIPS[i]
PATCH_NUMS=()
PATCH_ZIPS=()

for zip in "${ZIP_FILES[@]}"; do
  bname=$(basename "$zip")
  # Oracle patch filenames: p<NUMBER>_<VERSION>_Generic.zip
  patch_num=$(echo "$bname" | sed -n 's/^p\([0-9]*\)_.*/\1/p')
  if [ -n "$patch_num" ]; then
    PATCH_NUMS+=("$patch_num")
    PATCH_ZIPS+=("$zip")
  else
    echo "  WARNING: skipping '$bname' — filename does not match p<NUMBER>_... pattern"
  fi
done

if [ ${#PATCH_NUMS[@]} -eq 0 ]; then
  echo "No valid patch files found."
  exit 0
fi

# ---------------------------------------------------------------------------
# Query already-installed patches
# ---------------------------------------------------------------------------
INSTALLED_PATCHES=$(sql -S -name "$DB_CONN_NAME" <<'SQL' 2>/dev/null || true
set heading off feedback off pagesize 0 trimspool on
SELECT patch_number FROM apex_patches ORDER BY patch_number;
exit;
SQL
)

# Normalize to a single line for grep matching
INSTALLED_LIST=$(echo "$INSTALLED_PATCHES" | tr -d '[:space:]' | tr '\n' ' ')

# ---------------------------------------------------------------------------
# Determine which patches to apply (sorted ascending by patch number)
# ---------------------------------------------------------------------------
# Build a list of "patch_num|zip_path" lines, sorted by patch number
SORTED_PAIRS=""
i=0
while [ $i -lt ${#PATCH_NUMS[@]} ]; do
  SORTED_PAIRS="${SORTED_PAIRS}${PATCH_NUMS[$i]}|${PATCH_ZIPS[$i]}"$'\n'
  i=$((i + 1))
done
SORTED_PAIRS=$(echo "$SORTED_PAIRS" | sort -t'|' -k1 -n)

APPLY_NUMS=()
APPLY_ZIPS=()
SKIPPED=0

while IFS='|' read -r pnum pzip; do
  [ -z "$pnum" ] && continue
  if echo " $INSTALLED_LIST " | grep -q "$pnum"; then
    echo "  p$pnum — already installed, skipping"
    SKIPPED=$((SKIPPED + 1))
  else
    echo "  p$pnum — will be installed"
    APPLY_NUMS+=("$pnum")
    APPLY_ZIPS+=("$pzip")
  fi
done <<< "$SORTED_PAIRS"

if [ ${#APPLY_NUMS[@]} -eq 0 ]; then
  echo ""
  echo "All patches are already installed — nothing to do."
  exit 0
fi

echo ""
echo "${#APPLY_NUMS[@]} patch(es) to apply."

# ---------------------------------------------------------------------------
# Apply each patch
# ---------------------------------------------------------------------------
APPLIED=0
FAILED=0

i=0
while [ $i -lt ${#APPLY_NUMS[@]} ]; do
  patch_num="${APPLY_NUMS[$i]}"
  zip_path="${APPLY_ZIPS[$i]}"
  i=$((i + 1))

  echo ""
  echo "=== Applying patch $patch_num ==="

  # Create temp directory for extraction
  TEMP_DIR=$(mktemp -d)

  # Extract
  echo "  Extracting $(basename "$zip_path")..."
  unzip -q "$zip_path" -d "$TEMP_DIR"

  # Find catpatch.sql — could be at root or nested
  CATPATCH=$(find "$TEMP_DIR" -maxdepth 3 -name "catpatch.sql" -type f | head -1)

  if [ -z "$CATPATCH" ]; then
    echo "  ERROR: catpatch.sql not found in $(basename "$zip_path")" >&2
    FAILED=$((FAILED + 1))
    rm -rf "$TEMP_DIR"
    continue
  fi

  CATPATCH_DIR=$(dirname "$CATPATCH")
  echo "  Found catpatch.sql in: $(basename "$CATPATCH_DIR")"

  # Run catpatch.sql via SQLcl
  echo "  Running catpatch.sql..."
  (cd "$CATPATCH_DIR" && sql -name "$DB_CONN_NAME" <<SQL
@catpatch.sql
exit;
SQL
  )

  # Copy updated images if present
  PATCH_IMAGES=$(find "$TEMP_DIR" -type d -name "images" | head -1)
  if [ -n "$PATCH_IMAGES" ] && [ -d "$PATCH_IMAGES" ]; then
    echo "  Copying updated images to apex-images/..."
    cp -R "$PATCH_IMAGES"/. ./apex-images/ 2>/dev/null || true
  fi

  # Verify
  VERIFY=$(sql -S -name "$DB_CONN_NAME" <<SQL 2>/dev/null || true
set heading off feedback off pagesize 0 trimspool on
SELECT 'VERIFIED=' || patch_version FROM apex_patches WHERE patch_number = $patch_num;
exit;
SQL
  )

  if echo "$VERIFY" | grep -q "VERIFIED="; then
    VERSION=$(echo "$VERIFY" | grep "VERIFIED=" | sed 's/VERIFIED=//' | tr -d '[:space:]')
    echo "  Patch $patch_num applied successfully (version: $VERSION)"
    APPLIED=$((APPLIED + 1))
  else
    echo "  WARNING: Patch $patch_num may not have been applied correctly — check apex_patches"
    APPLIED=$((APPLIED + 1))
  fi

  # Clean up temp
  rm -rf "$TEMP_DIR"
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Patch Summary ==="
echo "Applied: $APPLIED"
echo "Skipped: $SKIPPED"
echo "Failed:  $FAILED"

if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "WARNING: Some patches failed. Check output above for details."
  exit 1
fi

echo ""
echo "Remember to restart ORDS to pick up any updated images:"
echo "  ./local-26ai.sh stop && ./local-26ai.sh start"
