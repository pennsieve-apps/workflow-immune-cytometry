#!/usr/bin/env python3
"""
Writes the two workflow definitions (workflow/*.json, the body of
POST /compute/workflows/definitions) from the step lists below. Each step's
cpu/memory comes from its app's app.yml runtime (the sibling repo
../processor-<app>), so the definitions follow the apps.

Each step pins the release tag of the checked-out commit of its app.

Usage: scripts/build-workflows.py
"""
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ORG = "https://github.com/pennsieve-apps"
COL, ROW = 260, 130  # canvas grid


def runtime(app: str) -> tuple[str, str]:
    path = ROOT.parent / f"processor-{app}" / "app.yml"
    if not path.exists():
        raise SystemExit(f"{path} not found: check out processor-{app} next to this repo")
    text = path.read_text()
    block = re.search(r"^runtime:\n((?:[ #].*\n?)*)", text, re.M).group(1)
    cpu = re.search(r"^\s+cpu:\s*(\d+)", block, re.M).group(1)
    mem = re.search(r"^\s+memory:\s*(\d+)", block, re.M).group(1)
    return cpu, mem


def release_tag(app: str) -> str:
    """The tag on origin that points at the checked-out commit (local tags can be stale)."""
    repo = ROOT.parent / f"processor-{app}"
    head = subprocess.run(["git", "-C", repo, "rev-parse", "HEAD"],
                          capture_output=True, text=True, check=True).stdout.strip()
    refs = subprocess.run(["git", "-C", repo, "ls-remote", "--tags", "origin"],
                          capture_output=True, text=True, check=True).stdout.split("\n")
    tags = sorted({ref.split("refs/tags/")[1].removesuffix("^{}")
                   for ref in refs if ref.startswith(head)},
                  key=lambda t: [int(n) for n in re.findall(r"\d+", t)])
    if not tags:
        raise SystemExit(f"processor-{app}: HEAD {head[:7]} has no release tag on origin")
    return tags[-1]


def step(id_, app, col, row, depends, links=(), params=None):
    cpu, mem = runtime(app)
    tag = release_tag(app)
    node = {
        "id": id_,
        "type": "processor",
        "sourceUrl": f"{ORG}/processor-{app}",
        "tag": tag,
        "dependsOn": list(depends),
        "position": {"x": 40 + COL * col, "y": 40 + ROW * row},
        "cpu": cpu,
        "memory": mem,
    }
    if links:
        node["inputs"] = [{"from": f, "output": o, "input": i} for f, o, i in links]
    if params:
        node["defaultParams"] = params
    return node


def output(id_, name, step_, out, folder, col, row, default=True):
    o = {"id": id_, "name": name, "from": {"step": step_, "output": out},
         "position": {"x": 40 + COL * col, "y": 40 + ROW * row}}
    if default:
        o["default"] = {"targetType": "Pennsieve Dataset", "params": {"TARGET_FOLDER": folder}}
    return o


FCS_INPUT = {
    "id": "fcs",
    "name": "FCS files",
    "description": "FCS files (flow, spectral or mass cytometry), one per sample, plus an "
                   "optional samples.csv sample sheet (file, sample_id, batch, condition, ...).",
    "position": {"x": 40, "y": 40 + ROW * 2},
}

PREP = lambda col, row: step("prep", "fcs-prep", col, row, ["fcs"])
QC = lambda col, row: step("qc", "peacoqc", col, row, ["prep"],
                           [("prep", "fcs", "fcs"), ("prep", "metadata", "metadata")])


def profiling():
    steps = [
        PREP(1, 2),
        QC(2, 2),
        step("doublets", "cleanet", 3, 2, ["qc", "prep"],
             [("qc", "fcs", "fcs"), ("prep", "metadata", "metadata")]),
        step("clusters", "flowsom", 4, 2, ["doublets", "prep"],
             [("doublets", "fcs", "fcs"), ("prep", "metadata", "metadata")]),
        step("umap", "cytometry-umap", 5, 1, ["clusters", "prep"],
             [("clusters", "cells", "cells"), ("prep", "metadata", "metadata")]),
        step("diffcyt", "diffcyt", 5, 3, ["clusters", "prep"],
             [("clusters", "clusters", "clusters"), ("prep", "metadata", "metadata")],
             {"CONDITION_COLUMN": "condition", "REFERENCE_LEVEL": "unstimulated",
              "BLOCK_COLUMN": "batch"}),
        step("report", "cytometry-report", 6, 2, ["prep", "qc", "doublets", "clusters", "umap", "diffcyt"],
             [("prep", "metadata", "metadata"), ("qc", "qc", "qc"), ("doublets", "qc", "doublets"),
              ("clusters", "clusters", "clusters"), ("umap", "embedding", "embedding"),
              ("diffcyt", "da", "da"), ("diffcyt", "ds", "ds")],
             {"REPORT_TITLE": "Immune Profiling & Differential Abundance"}),
    ]
    return {
        "name": "Immune Profiling & Differential Abundance",
        "summary": "FCS: QC, doublets, FlowSOM populations, UMAP, diffcyt DA/DS between conditions, report.",
        "description": (
            "High-dimensional immune profiling of flow, spectral or mass cytometry data, after the "
            "CyTOF workflow of Nowicka et al. (2017) and the FlowSOM protocol of Quintelier et al. "
            "(2021). Prepares and arcsinh-transforms the FCS files (FlowKit), removes acquisition "
            "anomalies (PeacoQC) and doublets (Cleanet), clusters cells with FlowSOM and labels the "
            "metaclusters from a marker table, embeds a subsample with UMAP, tests differential "
            "abundance and differential state between conditions with diffcyt (batch as a "
            "covariate), and writes an HTML report with tables."),
        "inputs": [FCS_INPUT],
        "processors": steps,
        "outputs": [
            output("report_out", "Report", "report", "report", "derivatives/immune-profiling/report", 7, 1),
            output("tables_out", "Tables", "report", "tables", "derivatives/immune-profiling/tables", 7, 2),
            output("clusters_out", "FlowSOM clusters", "clusters", "clusters",
                   "derivatives/immune-profiling/flowsom", 7, 3),
            output("da_out", "Differential abundance", "diffcyt", "da",
                   "derivatives/immune-profiling/diffcyt-da", 7, 4),
            output("ds_out", "Differential state", "diffcyt", "ds",
                   "derivatives/immune-profiling/diffcyt-ds", 7, 5),
            output("clean_fcs_out", "Cleaned FCS", "doublets", "fcs", "", 7, 6, default=False),
        ],
    }


def harmonization():
    ref = {"REFERENCE_COLUMN": "control", "REFERENCE_VALUES": "tcu1"}
    steps = [
        PREP(1, 2),
        QC(2, 2),
        step("assess-raw", "cytometry-batch-assess", 3, 0, ["qc", "prep"],
             [("qc", "fcs", "fcs"), ("prep", "metadata", "metadata")], {"LABEL": "raw", **ref}),
        step("cytonorm", "cytonorm", 3, 2, ["qc", "prep"],
             [("qc", "fcs", "fcs"), ("prep", "metadata", "metadata")],
             {"MODE": "controls", "BATCH_COLUMN": "batch", **ref}),
        step("cycombine", "cycombine", 3, 4, ["qc", "prep"],
             [("qc", "fcs", "fcs"), ("prep", "metadata", "metadata")],
             {"BATCH_COLUMN": "batch", "COVARIATE_COLUMN": "condition"}),
        step("assess-cytonorm", "cytometry-batch-assess", 4, 2, ["cytonorm", "prep"],
             [("cytonorm", "fcs", "fcs"), ("prep", "metadata", "metadata")],
             {"LABEL": "cytonorm", **ref}),
        step("assess-cycombine", "cytometry-batch-assess", 4, 4, ["cycombine", "prep"],
             [("cycombine", "fcs", "fcs"), ("prep", "metadata", "metadata")],
             {"LABEL": "cycombine", **ref}),
        step("report", "cytometry-report", 5, 2,
             ["prep", "qc", "assess-raw", "assess-cytonorm", "assess-cycombine", "cytonorm", "cycombine"],
             [("prep", "metadata", "metadata"), ("qc", "qc", "qc"),
              ("assess-raw", "assessment", "assessment"),
              ("assess-cytonorm", "assessment", "assessment"),
              ("assess-cycombine", "assessment", "assessment"),
              ("cytonorm", "qc", "normalization"), ("cycombine", "qc", "normalization")],
             {"REPORT_TITLE": "Multi-batch Harmonization & QC"}),
    ]
    return {
        "name": "Multi-batch Harmonization & QC",
        "summary": "FCS: QC, batch-effect EMD per marker, CytoNorm vs cyCombine correction, before/after report.",
        "description": (
            "Measures and corrects batch effects in a multi-batch cytometry cohort. Prepares and "
            "arcsinh-transforms the FCS files (FlowKit), removes acquisition anomalies (PeacoQC), "
            "scores every batch and marker by Earth Mover's Distance against a replicate control "
            "and the other batches, normalizes with CytoNorm (on the replicate control) and with "
            "cyCombine (preserving the condition), scores both corrected cohorts the same way, and "
            "writes a report comparing the methods."),
        "inputs": [FCS_INPUT],
        "processors": steps,
        "outputs": [
            output("report_out", "Report", "report", "report", "derivatives/batch-harmonization/report", 6, 1),
            output("tables_out", "Tables", "report", "tables", "derivatives/batch-harmonization/tables", 6, 2),
            output("cytonorm_fcs_out", "CytoNorm-normalized FCS", "cytonorm", "fcs",
                   "derivatives/batch-harmonization/cytonorm-fcs", 6, 3),
            output("cycombine_fcs_out", "cyCombine-corrected FCS", "cycombine", "fcs", "", 6, 4, default=False),
        ],
    }


def main():
    out = ROOT / "workflow"
    out.mkdir(exist_ok=True)
    for name, wf in (("immune-profiling-differential-abundance", profiling()),
                     ("multi-batch-harmonization-qc", harmonization())):
        assert len(wf["summary"].encode()) <= 100, (name, len(wf["summary"].encode()))
        (out / f"{name}.json").write_text(json.dumps(wf, indent=2) + "\n")
        print(f"wrote workflow/{name}.json ({len(wf['processors'])} steps)")


if __name__ == "__main__":
    main()
