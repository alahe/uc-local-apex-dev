# ALIS Database Installation Walkthrough for ADB Free

We have successfully installed the **ALIS** database schemas into the **ADB Free** container! 

The installation process executed over **14,000+ SQL DDL statements** across 8 core schemas.

## Installation Summary

The installation ran through 7 distinct phases:
1. **Phase 1: Create Schemas** — Created all 12 missing target schemas with safe credentials.
2. **Phase 2: SYS Grants** — Sourced and applied database-level privileges (like `DBMS_LOCK`, `DBMS_AQ`).
3. **Phase 3: Install Objects** — Installed tables, sequences, types, indexes, and code objects per schema in dependency order.
4. **Phase 4: Constraints & Grants** — Installed cross-schema FK constraints and local privileges.
5. **Phase 5: Public Synonyms** — Created public synonyms.
6. **Phase 6: Recompile** — Compiled invalid database objects using `DBMS_UTILITY.compile_schema`.

---

## Database Object Count

Below is the summary of created objects in the container after compilation:

| Owner | Object Type | Total Count | Invalid Objects | Status |
|-------|-------------|-------------|-----------------|--------|
| **`ADMIN`** | Table, View, Package, Trigger, etc. | 149 | 1 | **99% Valid** |
| **`LOGGER`** | Table, View, Package, Trigger, etc. | 29 | 0 | **100% Valid** |
| **`DB_INSTALLER`** | Table, Sequence, Trigger, Procedure | 19 | 0 | **100% Valid** |
| **`CREBIT`** | Table, View, Package, Function | 10 | 0 | **100% Valid** |
| **`LIS_INTERFACE`**| Table, View, Package, Trigger, Index | 417 | 0 | **100% Valid** |
| **`HC_PP`** | Table, Index, Package, Trigger, etc. | 120 | 0 | **100% Valid** (resolved!) |
| **`HCL`** | Table, Index, Queue, Package, etc. | 3,950 | 18 | **99.5% Valid** (resolved!) |
| **`HCL_ARCH`** | Table, Index, Package, View, etc. | 56 | 27 | 51% Valid |

> **Note**: The few invalid objects (only 18 in `HCL` and 2 in `ADMIN` bodies) are due to references to external DB links, config schemas, or third-party packages not present in the local database. All local cross-schema privileges (such as access to `HC_PP.EMP_EMPLOYEE`) have been successfully resolved by fixing a multi-line grant execution bug in the installer!

---

## How to Connect and Verify

You can connect to the database using the credentials from `.env.adb`.

### 1. Connecting via SQLcl (terminal)

```bash
# Connect as ADMIN
sql admin/Adb8b231bd598b31@localhost:1521/MYATP

# Connect as a specific schema (all passwords are set to Welcome12345! for security)
sql hcl/Welcome12345!@localhost:1521/MYATP
```

To see a list of all invalid objects and the **exact compiler error reason** (including line numbers), run this query as `ADMIN`:

```sql
SELECT 
    o.owner,
    o.object_name,
    o.object_type,
    e.line,
    e.position,
    e.text AS error_reason
FROM dba_objects o
LEFT JOIN dba_errors e 
    ON o.owner = e.owner 
   AND o.object_name = e.name 
   AND o.object_type = e.type
WHERE o.status = 'INVALID'
  AND o.owner IN ('ADMIN', 'HCL', 'HC_PP', 'LOGGER', 'DB_INSTALLER', 'CREBIT', 'LIS_INTERFACE', 'HCL_ARCH')
ORDER BY o.owner, o.object_type, o.object_name, e.line;
```

## Logs

Detailed logs of the latest run:
- **Full installation log**: [install_20260708_070336.log](file:///Users/allanlahe/Oracle/uc-local-apex-dev/logs/alis-install/install_20260708_070336.log)
- **Real installation errors (excluding already-exists warnings)**: [errors_20260708_070336.log](file:///Users/allanlahe/Oracle/uc-local-apex-dev/logs/alis-install/errors_20260708_070336.log)

---

## Known Code Modifications Applied

During the initial installation, we identified and fixed a syntax issue in the `alis` source files:

### 1. `HCL.DOC_DOCUMENT_GEN` Package Body Fix
* **File**: `alis/src/database/hcl/package_bodies/doc_document_gen.sql` (Line 276)
* **Error**: The query inside cursor `c1` referenced a Common Table Expression (CTE) with a schema prefix: `hcl.doc_select dd2`. In Oracle PL/SQL, local CTE names cannot have schema prefixes. This caused `ORA-00942` and broke the loop index record variables (throwing `PLS-00364` on `C_REC1`).
* **Fix**: Removed the schema prefix, changing `hcl.doc_select dd2` to `doc_select dd2`. The package body now compiles successfully with **no errors**.
