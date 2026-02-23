#!/usr/bin/env bash
# Migrates apple-health/raw/YYYY/MM/DD/<ts>.json
#         → apple-health/YYYY/MM/DD/sample-<ts>.json
#
# Usage: ./scripts/migrate-raw-to-flat.sh <data-dir>
# Example: ./scripts/migrate-raw-to-flat.sh ~/my-life-db/data

set -euo pipefail

DATA_DIR="${1:?Usage: $0 <data-dir>}"
APPLE_HEALTH="$DATA_DIR/imports/fitness/apple-health"
RAW_DIR="$APPLE_HEALTH/raw"

if [ ! -d "$RAW_DIR" ]; then
    echo "Nothing to migrate: $RAW_DIR does not exist"
    exit 0
fi

moved=0
skipped=0

while IFS= read -r -d '' src; do
    # src = .../raw/2026/02/20/2026-02-20T09-58-48Z.json
    rel="${src#$RAW_DIR/}"                  # 2026/02/20/2026-02-20T09-58-48Z.json
    dir=$(dirname "$rel")                   # 2026/02/20
    filename=$(basename "$rel")             # 2026-02-20T09-58-48Z.json
    dest_dir="$APPLE_HEALTH/$dir"
    dest="$dest_dir/sample-$filename"

    mkdir -p "$dest_dir"

    if [ -f "$dest" ]; then
        echo "SKIP (exists): $dest"
        ((skipped++))
        continue
    fi

    mv "$src" "$dest"
    echo "MOVED: raw/$rel → $dir/sample-$filename"
    ((moved++))
done < <(find "$RAW_DIR" -name "*.json" -print0)

echo ""
echo "Done. Moved: $moved, Skipped: $skipped"

# Remove raw/ if now empty
if [ -z "$(find "$RAW_DIR" -name "*.json" 2>/dev/null)" ]; then
    rm -rf "$RAW_DIR"
    echo "Removed empty raw/ directory"
fi
