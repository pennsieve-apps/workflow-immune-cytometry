# Brief for building an app of the immune cytometry workflows

You are building one or more Pennsieve processor apps, each in its own git repo under
`~/code/pennsieve/<repo>` (remote `git@github.com:pennsieve-apps/<repo>.git`; the empty
GitHub repo already exists, public). The apps form two workflows for Penn's Immune
Health project:

- **A. Immune Profiling & Differential Abundance:**
  `fcs-prep → peacoqc → cleanet → flowsom → {cytometry-umap, diffcyt} → cytometry-report`
- **B. Multi-batch Harmonization & QC:** `fcs-prep → peacoqc → {batch-assess(LABEL=raw),
  cytonorm → batch-assess(LABEL=cytonorm), cycombine → batch-assess(LABEL=cycombine)}
  → cytometry-report`

## Read first

1. `~/code/pennsieve/workflow-immune-cytometry/docs/conventions.md`: the file and port
   contract between apps. Follow it exactly.
2. A finished app to copy the layout, tone and level of care from:
   `~/code/pennsieve/processor-brain-volumetrics` (Python: `processor/entry.py`, `main.py`,
   `handler.py` for Lambda, Makefile, tests, `docker-compose.yml`, `dev.env`) and
   `~/code/pennsieve/processor-synthseg` (README with port table, parameters, runtime
   section with measured memory, `THIRD_PARTY.md`, Citations).
3. The app manifest schema: `~/code/pennsieve/workflow-immune-cytometry/docs/app-manifest.v1.schema.json`.
   Validate `app.yml` against it (`python3 -m venv` + `pip install jsonschema pyyaml`
   in your scratch dir).

## Every repo has

`app.yml` (with `# yaml-language-server: $schema=https://schemas.pennsieve.io/app-manifest/v1.json`,
`schemaVersion: "1.0"`, `application` with name/description/type processor/tags,
`runtime` cpu/memory/computeTypes/timeoutSeconds, `parameters`, `inputs`, `outputs`),
`Dockerfile` (linux/amd64, pinned base image and package versions, non-interactive,
no network at run time, as small as reasonable), `processor/` code, `tests/` (unit tests
that run without Docker on a tiny synthetic fixture), `Makefile` (`test`, `fixture`,
`run` = docker compose over a fixture into `data/output/`, `clean`),
`docker-compose.yml`, `dev.env`, `sample-input/README.md` (how to get real input),
`README.md`, `THIRD_PARTY.md` (every bundled component with its licence),
`LICENSE` (Apache-2.0 for our code; if the app links GPL code in-process the image is
GPL, so say so in THIRD_PARTY.md — R packages loaded by our R script are fine to
redistribute under their licences), `VERSION` (`0.1.0`), `.gitignore` (data/output,
data/fixture, caches).

R apps: write the R logic as an `R/` script called from a thin entry (R-only is fine:
`Rscript /app/R/main.R`). Use a slim base: `rocker/r-ver:<pinned 4.x>` with binary
packages from Posit Public Package Manager pinned to a snapshot date, Bioconductor
packages via `BiocManager` pinned to the matching release, GitHub-only packages via
`remotes::install_github("<owner>/<repo>@<commit sha>")`. Record versions in
`provenance.json` (`packageVersion()`).

## README

Model it on processor-synthseg's: what the app does and why (for an immunologist),
port table, parameters table (defaults, what each does), outputs with columns,
runtime (cpu/memory chosen and **measured** peak memory and wall time on the demo data,
saying what you measured on: amd64 emulation on an M-series Mac), limitations, licences,
and a **Citations** section.

**Citations must be real.** For each paper: authors, title, journal, year, volume:pages,
DOI and PMID. Check every one on PubMed (E-utilities: `https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=<PMID>&retmode=json`)
or, for papers not in PubMed, via `https://api.crossref.org/works/<DOI>`, and make sure
the title, first author and year match. Never cite something you could not check;
cite the software repo instead. Already verified (re-check anyway): flowCore PMID
19358741; FlowKit 34804056; PeacoQC 34549881; Cleanet 41065042; FlowSOM 25573116 and the
Nat Protoc FlowSOM protocol 34172973; UMAP for single-cell 30531897; diffcyt 31098416;
CytoNorm 31633883; CytoNorm 2.0 39871681; cyCombine 35361793; Nowicka CyTOF workflow
28663787; Liechti 2021 guide 34489590; Mathew 2020 Penn COVID immunotypes 32669297;
Logicle 16604519. The demo data: Koenig Z, Andorf S, Tilburgs T, Eswar S.
CytoBatchFlagR: Spectral flow cytometry dataset. Zenodo 2025. doi:10.5281/zenodo.15388817
(CC BY 4.0).

## Test on real data

Demo data: `~/code/pennsieve/workflow-immune-cytometry/data/zenodo-15388817/` (24 FCS
files + `samples.csv`; read-only, do not modify). Upstream outputs, once other builders
produce them, will be in `~/code/pennsieve/workflow-immune-cytometry/data/work/<step>/`
(e.g. `data/work/prep/fcs`, `data/work/prep/metadata`). If what you need isn't there
yet, write your own fixture generator in `tests/make_fixture.py` that follows the
contract (e.g. subsample raw files and arcsinh-transform marker channels with cofactor
6000) and say so in your report. Local Docker has 8 GB and is shared with other
builders running in parallel: test on subsamples (e.g. 20k events per file), give
`docker run` a `--memory` limit, measure peak memory with `docker stats` or
`/sys/fs/cgroup/memory.peak`, and remove your test containers. Build images
`--platform linux/amd64`.

## Git

`git init -b main`, commit with clear messages (end each with
`Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`), add the remote, and **push
`main`** once tests pass and the Docker run succeeded on real data. Do NOT tag or create
releases; the coordinator does that.

## Report back

Short report: repo path, commit(s), ports and parameters as built, what you ran it on
and the results (numbers), measured memory/time, image size, chosen cpu/memory,
citations with their PMIDs/DOIs and how you verified them, open problems.
