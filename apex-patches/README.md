Place your APEX Patch Set Bundle ZIP files (downloaded from My Oracle Support) in this directory.

Example: p39179920_2610_Generic.zip

These files are excluded from Git via .gitignore.

## Optional: fetch automatically from an internal mirror

Instead of everyone downloading patch bundles from My Oracle Support by
hand, you can host the same ZIP files on an internal artifact repository and
have `scripts/apply-patches.sh` fetch missing ones automatically. Set these
in `.env`:

```bash
APEX_PATCHES_MIRROR_URL="https://<internal-repo-host>/<path-to-folder>"
APEX_PATCHES_MANIFEST="p39179920_2610_Generic.zip,p39355255_2610_Generic.zip"
```

`APEX_PATCHES_MANIFEST` is a comma-separated list of the exact filenames
uploaded to `APEX_PATCHES_MIRROR_URL`. Any file already present locally in
this directory is left untouched; only missing ones are fetched. Leave both
variables empty (the default) to keep the manual workflow described above.
