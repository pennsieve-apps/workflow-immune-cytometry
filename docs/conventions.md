# Conventions shared by the immune cytometry apps

Every app in the two workflows (Immune Profiling & Differential Abundance, Multi-batch
Harmonization & QC) follows this contract, so any step's output can be linked to any
other step's input without glue.

## Runtime contract (Pennsieve processors)

- Read from `$INPUT_DIR`, write to `$OUTPUT_DIR`. Parameters arrive as environment
  variables named as in `app.yml`. Never write elsewhere except `/tmp`.
- One output port: it is the whole `$OUTPUT_DIR`. Two or more outputs: each is written
  to `$OUTPUT_DIR/<name>/`.
- Inputs with several ports use `placement: subfolder`: each arrives at
  `$INPUT_DIR/<name>/`. Apps must also work when no links are used (everything merged
  side by side at the root of `$INPUT_DIR`), by finding files by their names anywhere
  under `$INPUT_DIR` (follow symlinks; INPUT_DIR entries are symlinks).
- Several links may feed the same input port; their entries land side by side in the
  same folder, and two entries with the same name fail the run. So an app that can run
  more than once in a workflow (batch-assess) writes everything under a folder named
  after its `LABEL` parameter.
- Port names: lowercase letters, digits and `-` (no underscores).
- Each output folder gets a `provenance.json`: app name + version (from `VERSION`),
  tool versions, parameters, inputs seen (relative paths), timings, per-sample status.
- A sample that fails is logged and skipped; the step fails only when every sample
  failed or no input was found. Exit code non-zero on failure.
- Logs go to stdout, one line per sample with counts and timings.
- Memory: never hold all events of all samples at once. Per-file work streams one file
  at a time; pooled methods train on per-sample subsamples (seeded).
- Reproducible: every random step takes `SEED` (default `42`).

## Files

### FCS files (`fcs` ports)

- `<sample_id>.fcs`, FCS 3.1, float32, one per sample. `sample_id` matches `[A-Za-z0-9_-]+`.
- Values of **marker** channels are arcsinh-transformed by `fcs-prep` (see `panel.csv`);
  scatter, `Time` and other channels are left as acquired. Downstream apps never
  re-transform; they rewrite files with the same channels and keywords (`$PnN`, `$PnS`)
  and only drop events (QC, doublets) or change marker values (normalization).
- Apps add keywords recording what they did, e.g. `PENNSIEVE_PREP=transform=arcsinh`,
  `PENNSIEVE_QC=peacoqc;removed=1234`.

### `samples.csv` (in the `metadata` port, written by `fcs-prep`)

One row per sample. Required columns: `sample_id`, `file` (original file name),
`batch`, `condition`, `n_events`. Any extra columns from the user's sample sheet are
carried through unchanged (e.g. `control`, `donor`, `timepoint`).

`fcs-prep` reads an optional sample sheet from its input (`SAMPLE_SHEET`, default
`samples.csv`, a CSV with a `file` column matching FCS file names). Without one:
`sample_id` = sanitised file stem, `batch` = the file's `$DATE` keyword, `condition` =
`NA`.

### `panel.csv` (in the `metadata` port)

One row per channel kept: `channel` (`$PnN`), `marker` (`$PnS`, or the channel name
when empty), `type` (`marker` | `scatter` | `time` | `other`), `cofactor` (empty unless
transformed), `clustering` (`true`/`false`: use for clustering; default true for
lineage markers, `PANEL_OVERRIDES` can change it), `state` (`true`/`false`: a functional
/ state marker for differential-state tests).

Channels missing from some samples, or carrying a different marker in some samples,
are dropped from every output file (the panel is the intersection of channel+marker
across samples); `prep.json` lists them per sample. The demo panel changed at batch 05:
`BV785-A` (CD28) is absent in 05–06, `PerCP-A` is CD163 in 01–04 but CD28 in 05–06,
`APC-A` is GITR in 01–04 but CCR4 in 05–06; all three are dropped, leaving 25 markers.

As built (fcs-prep v0.1.0, demo output in `data/work/prep/`): 33 channels (6 scatter,
`AF-A`, 25 markers, `Time`), cofactor 6000 for spectral (5 CyTOF, 150 conventional,
after cyCombine's Methods). Clustering markers (14): HELIOS, CCR7, CD4, CD56, CD3, CD19,
CD8, CD103, CD16, CD14, CD27, CCR6, CD45RA, FOXP3. State markers (10): GZMB, GNLY, CD95,
CD69, PFN, HLADR, CD25, PD1, CD39, TIGIT. CD45 is neither. `Time` is kept as acquired
(not multiplied by `$TIMESTEP`), and `$PnR` is raised to cover the data: SpectroFlo
writes `$PnR=129` for Time while values reach ~1e6, and flowCore's `read.FCS` truncates
at `$PnR` by default, so read raw demo files with `truncate_max_range = FALSE`.

### Pre-gating raw mass cytometry (`fcs-prep` ≥ 0.1.2)

Raw CyTOF files still contain normalisation beads, debris and dead cells. With `PREGATE=auto`
(default), `fcs-prep` gates them out before anything else when the panel has bead, DNA or
viability channels: beads out (140Ce etc.), DNA⁺ events on Ir191/Ir193 (doublets are left for
`cleanet`), live cells on the viability channel. Thresholds come from each file's own density
(valleys between modes, with floors and caps); per-sample counts are in `metadata/gating.csv`,
plots in `metadata/gates/`, and a `pregate` section in `prep.json`. Pre-gated data (no such
channels, e.g. the spectral demo) passes through unchanged. Viability, DNA, bead, barcode and
cisplatin channels are neither clustering nor state markers.

### Cell subsamples and tables

- Tables are CSV (UTF-8, header row, `.` decimal). Long format where it is natural:
  `sample_id, cluster, metacluster, n` and so on.
- Cell-level subsamples for plotting: `cells.csv.gz` with `sample_id`, the clustering
  columns, then marker columns named by `marker`.

## Demo data

`data/zenodo-15388817/` (gitignored): CytoBatchFlagR spectral flow dataset, Koenig Z,
Andorf S, Tilburgs T, Eswar S, Zenodo 2025, doi:10.5281/zenodo.15388817, CC BY 4.0.
Cytek Aurora, healthy adult peripheral blood leukocytes pre-gated to CD45+CD14− live
single cells, 28 markers. Batches 01–06 × {tcu1, tcu2 (unstimulated), tcs3, tcs4
(anti-CD3/CD28 + IL-2, 7 days)}: 24 files, 25k–600k events each, 10.4 M events,
1.46 GB. Spectrally unmixed already (`$SPILLOVER` is the identity), so no compensation.
`samples.csv` there is our sample sheet (`file, sample_id, batch, condition, control`).

For local tests use a subsample (e.g. 20k events per file) unless measuring memory and
time; Docker on the dev Mac has 8 GB.
