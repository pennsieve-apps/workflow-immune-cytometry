#!/usr/bin/env bash
# Downloads the demo data: the CytoBatchFlagR spectral flow cytometry dataset
# (Koenig Z, Andorf S, Tilburgs T, Eswar S; Zenodo 2025; doi:10.5281/zenodo.15388817;
# CC BY 4.0), batches 01-06 by default (24 FCS files, 1.46 GB), checks every file's
# MD5 against the Zenodo record, and writes samples.csv, the sample sheet the
# fcs-prep step reads (file, sample_id, batch, condition, control).
#
# Usage: scripts/fetch-sample-data.sh [out-dir] [batches]
#   out-dir  default data/zenodo-15388817
#   batches  default "01 02 03 04 05 06"; "all" for the 18 batches (72 files, 3.7 GB)
set -euo pipefail
OUT="${1:-data/zenodo-15388817}"
BATCHES="${2:-01 02 03 04 05 06}"
mkdir -p "$OUT"
RECORD="$OUT/record.json"
curl -sfL https://zenodo.org/api/records/15388817 -o "$RECORD"

python3 -I - "$RECORD" "$BATCHES" > "$OUT/manifest.txt" <<'EOF'
import json, sys
record, batches = json.load(open(sys.argv[1])), sys.argv[2].split()
for f in record["files"]:
    key = f["key"]
    wanted = not key.endswith(".fcs") or batches == ["all"] or key[1:3] in batches
    if wanted:
        print(key, f["checksum"].removeprefix("md5:"), f["links"]["self"])
EOF

md5of() { if command -v md5sum >/dev/null; then md5sum "$1" | cut -d' ' -f1; else md5 -q "$1"; fi; }
while read -r key md5 url; do
  if [ ! -f "$OUT/$key" ] || [ "$(md5of "$OUT/$key")" != "$md5" ]; then
    echo "fetch $key"; curl -sfL -o "$OUT/$key" "$url"
  fi
  [ "$(md5of "$OUT/$key")" = "$md5" ] || { echo "MD5 mismatch: $key" >&2; exit 1; }
done < "$OUT/manifest.txt"

# Sample sheet: tcu* = unstimulated controls, tcs* = stimulated 7 days (anti-CD3/CD28 + IL-2).
# The donor is the first word of each file's $TUBENAME keyword ("181C 2" -> 181C): tcu1/tcu2
# are aliquots of donor 181C in every batch; the stimulated samples come from 199C or 198C.
python3 -I - "$OUT" <<'EOF'
import csv, os, sys
out = sys.argv[1]

def tubename(path):
    with open(path, "rb") as f:
        head = f.read(58)
        start, end = int(head[10:18]), int(head[18:26])
        f.seek(start)
        text = f.read(end - start + 1)
    delim = chr(text[0])
    parts = text[1:].decode("latin-1").split(delim)
    keywords = {parts[i].upper(): parts[i + 1] for i in range(0, len(parts) - 1, 2)}
    return keywords.get("TUBENAME", "")

rows = [r for r in csv.DictReader(open(os.path.join(out, "Table_2.csv")))
        if os.path.exists(os.path.join(out, r["file"]))]
with open(os.path.join(out, "samples.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["file", "sample_id", "batch", "condition", "control", "donor"])
    for r in rows:
        cond = "stimulated" if r["control"].startswith("tcs") else "unstimulated"
        donor = tubename(os.path.join(out, r["file"])).split(" ")[0] or "NA"
        w.writerow([r["file"], r["sample_id"], r["batch"], cond, r["control"], donor])
print(f"{len(rows)} samples -> {out}/samples.csv")
EOF
