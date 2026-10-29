#!/usr/bin/env bash
# Downloads the second demo dataset, mass cytometry (CyTOF) of renal transplant recipients and
# healthy donors (Kowli S, Minocherhomji S, Martinez OM, Busque S, Lebrec H, Maecker HT; Zenodo
# 2025; doi:10.5281/zenodo.17238592; CC BY 4.0; paper: ImmunoHorizons 2025;9(4):vlae013,
# doi:10.1093/immhor/vlae013), checks the zips' MD5s against the Zenodo record, and extracts the
# unstimulated samples used here under clean names with a sample sheet (samples.csv).
#
# Selection: every donor's pre-transplant and 6-month unstimulated sample (10 patients, one
# without a 6-month sample; 11 healthy donors) and the HIMC control PBMC (the same donor, run in
# each of the 7 batches): 48 files, ~2.1 GB. The batch of a sample is the HIMC run it was
# acquired with: the date prefix of its file name is that run's date or the day before.
#
# Usage: scripts/fetch-cytof-data.sh [out-dir]     (default data/kowli-17238592)
set -euo pipefail
OUT="${1:-data/kowli-17238592}"
mkdir -p "$OUT/zips" "$OUT/fcs"
curl -sfL https://zenodo.org/api/records/17238592 -o "$OUT/record.json"

python3 -I - "$OUT/record.json" "$OUT/zips" <<'EOF'
import hashlib, json, os, sys, urllib.request
record, out = json.load(open(sys.argv[1])), sys.argv[2]
def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()
for f in record["files"]:
    if f["key"] not in ("US.zip", "HIMC.zip"):
        continue
    path, want = os.path.join(out, f["key"]), f["checksum"].removeprefix("md5:")
    if not (os.path.exists(path) and md5(path) == want):
        print("fetch", f["key"], flush=True)
        urllib.request.urlretrieve(f["links"]["self"], path)
    if md5(path) != want:
        sys.exit(f"MD5 mismatch: {f['key']} (try again: Zenodo downloads sometimes stop early)")
    print(f["key"], "md5 ok", flush=True)
EOF

python3 -I - "$OUT/zips" "$OUT/fcs" <<'EOF'
import csv, os, re, sys, zipfile
zips, out = sys.argv[1], sys.argv[2]
# HIMC control runs (MMDDYYYY): batch01..batch07 in date order.
RUNS = ["04202018", "07132018", "10172018", "12062018", "12142018", "12192018", "02132019"]
key = lambda d: d[4:] + d[:4]
def batch_of(date):
    from datetime import date as D
    t = D(int(date[4:]), int(date[:2]), int(date[2:4]))
    for i, r in enumerate(RUNS):
        if 0 <= (D(int(r[4:]), int(r[:2]), int(r[2:4])) - t).days <= 1:
            return f"batch{i + 1:02d}"
    raise SystemExit(f"no HIMC run on or the day after {date}")
def timepoint(name):
    n = name.lower()
    if "pre tx" in n: return "pre_tx"
    m = re.search(r"(\d)\s+months?", n)
    return f"month_{m.group(1)}" if m else None

rows = []
for z in ("US.zip", "HIMC.zip"):
    with zipfile.ZipFile(os.path.join(zips, z)) as zf:
        for name in zf.namelist():
            base = name.rsplit("/", 1)[-1]
            if "__MACOSX" in name or not base.lower().endswith(".fcs"):
                continue
            date = base[:8]
            if z == "HIMC.zip":
                if "pma" in base.lower():
                    continue
                b = batch_of(date)
                row = dict(sample_id=f"himc_{b}", group="control", timepoint="control", donor="HIMC330", control="himc")
            else:
                tp = timepoint(base)
                if tp not in ("pre_tx", "month_6"):
                    continue
                m = re.search(r"/(Pt|HD)_(\d+)/", name)
                group = "patient" if m.group(1) == "Pt" else "healthy"
                donor = f"{m.group(1).lower()}{int(m.group(2)):02d}"
                b = batch_of(date)
                row = dict(sample_id=f"{donor}_{tp}", group=group, timepoint=tp, donor=donor, control="sample")
            row.update(batch=b, file=row["sample_id"] + ".fcs", source_file=name)
            target = os.path.join(out, row["file"])
            if not os.path.exists(target):
                with zf.open(name) as src, open(target, "wb") as dst:
                    while True:
                        chunk = src.read(1 << 22)
                        if not chunk: break
                        dst.write(chunk)
            rows.append(row)

rows.sort(key=lambda r: (r["batch"], r["group"], r["sample_id"]))
cols = ["file", "sample_id", "batch", "group", "timepoint", "donor", "control", "source_file"]
with open(os.path.join(out, "samples.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=cols); w.writeheader(); w.writerows(rows)
from collections import Counter
print(len(rows), "files ->", out)
print(Counter((r["group"], r["timepoint"]) for r in rows))
print(Counter(r["batch"] for r in rows))
EOF
