# Immune cytometry workflows on Pennsieve

Two end-to-end workflows for high-dimensional flow, spectral and mass cytometry, built from
reusable, open-source Pennsieve apps. They are a demonstration of Pennsieve workflows and a
starting point for the immunology community and Penn's Immune Health work, in the tradition of
deep immune profiling studies such as Mathew et al. (2020).

| Workflow | Question it answers | Definition |
|---|---|---|
| **Immune Profiling & Differential Abundance** | Which immune populations and activation states differ between conditions? | `workflow/immune-profiling-differential-abundance.json` |
| **Multi-batch Harmonization & QC** | How large are the batch effects in a cohort, and which correction removes them best? | `workflow/multi-batch-harmonization-qc.json` |

## Immune Profiling & Differential Abundance

```
fcs ─► fcs-prep ─► peacoqc ─► cleanet ─► flowsom ─┬─► cytometry-umap ─┐
         │ metadata                                └─► diffcyt ────────┼─► cytometry-report
         └────────────── (metadata to every step) ─────────────────────┘
```

This follows the analysis of Nowicka et al. (2017) and the FlowSOM protocol of Quintelier et al. (2021):

1. Prepare and arcsinh-transform every file.
2. Remove acquisition anomalies and doublets.
3. Cluster with FlowSOM, train on per-sample subsamples, then map every cell; label metaclusters from a marker table.
4. Embed a subsample with UMAP.
5. Test differential abundance and differential state between conditions with diffcyt, with batch as a covariate.
6. Write a report. For each significant result it shows how consistent the result is from batch to batch.

## Multi-batch Harmonization & QC

```
                        ┌─► cytometry-batch-assess (raw) ────────────────┐
fcs ─► fcs-prep ─► peacoqc ─► cytonorm ─► cytometry-batch-assess (cytonorm) ─┼─► cytometry-report
                        └─► cycombine ─► cytometry-batch-assess (cycombine) ─┘
```

1. Score every batch × marker with the Earth Mover's Distance (EMD), against a replicate control
   sample present in every batch and against the other batches within each condition.
2. Correct the cohort two ways:
   - CytoNorm, trained on the replicate control.
   - cyCombine, preserving the biological condition.
3. Score both corrected cohorts the same way, so the report can compare raw, CytoNorm and cyCombine
   on equal terms.

The same app runs three times in this workflow, with a different `LABEL` each time.

## Apps

All apps are in the [`pennsieve-apps`](https://github.com/pennsieve-apps) GitHub organization, released
to the Pennsieve App Store, and documented in their own README: method, ports, parameters, measured
runtime and memory, licences and citations.

| Step | App | Tool | Runtime (demo, 24 files, 10.2 M events) |
|---|---|---|---|
| prep | [processor-fcs-prep](https://github.com/pennsieve-apps/processor-fcs-prep) | FlowKit | Panel harmonization, compensation (when needed), arcsinh transform, sample sheet; 26 s |
| qc | [processor-peacoqc](https://github.com/pennsieve-apps/processor-peacoqc) | PeacoQC | Removes flow-rate and signal anomalies over time; 4 min |
| doublets | [processor-cleanet](https://github.com/pennsieve-apps/processor-cleanet) | Cleanet | Doublet detection from protein expression patterns; 30 min |
| clusters | [processor-flowsom](https://github.com/pennsieve-apps/processor-flowsom) | FlowSOM | SOM + metaclusters, labelled from a marker table; 5 min |
| umap | [processor-cytometry-umap](https://github.com/pennsieve-apps/processor-cytometry-umap) | umap-learn | UMAP of 100k cells; 2 min (can run as Lambda) |
| diffcyt | [processor-diffcyt](https://github.com/pennsieve-apps/processor-diffcyt) | diffcyt (edgeR / limma) | Differential abundance and state; 8 s (can run as Lambda) |
| assess-* | [processor-cytometry-batch-assess](https://github.com/pennsieve-apps/processor-cytometry-batch-assess) | SciPy | Batch × marker EMD and flags; 6 s (can run as Lambda) |
| cytonorm | [processor-cytonorm](https://github.com/pennsieve-apps/processor-cytonorm) | CytoNorm 2.0 | Quantile normalization on replicate controls; 10 min |
| cycombine | [processor-cycombine](https://github.com/pennsieve-apps/processor-cycombine) | cyCombine | ComBat per SOM node, condition preserved; 2 min |
| report | [processor-cytometry-report](https://github.com/pennsieve-apps/processor-cytometry-report) | pandas, matplotlib | Offline HTML report and tables for either workflow; 6 s (can run as Lambda) |

Runtimes were measured under amd64 emulation on an Apple-silicon Mac. Every step loops over all the
samples it receives, so one run processes the whole cohort.

The apps share one contract for files and ports, described in [`docs/conventions.md`](docs/conventions.md):

- `samples.csv` and `panel.csv` metadata.
- Transformed FCS 3.1 files.
- One output folder per output port.

## Workflow interface

Both workflows take one input and bind outputs to dataset folders when they run.

**Input.** `fcs`: the FCS files, plus an optional `samples.csv` sample sheet with columns `file`,
`sample_id`, `batch`, `condition` and any extras such as `donor` or `control`. The sheet's columns
travel with the data to every step.

**Outputs, Immune Profiling & Differential Abundance:**

| Output | Default destination |
|---|---|
| `report_out` | `derivatives/immune-profiling/report` |
| `tables_out` | `derivatives/immune-profiling/tables` |
| `clusters_out` | `derivatives/immune-profiling/flowsom` |
| `da_out` | `derivatives/immune-profiling/diffcyt-da` |
| `ds_out` | `derivatives/immune-profiling/diffcyt-ds` |
| `clean_fcs_out` | none; pick a destination |

**Outputs, Multi-batch Harmonization & QC:**

| Output | Default destination |
|---|---|
| `report_out` | `derivatives/batch-harmonization/report` |
| `tables_out` | `derivatives/batch-harmonization/tables` |
| `cytonorm_fcs_out` | `derivatives/batch-harmonization/cytonorm-fcs` |
| `cycombine_fcs_out` | none; pick a destination |

**Defaults set for the demo.** Change these per step for your own study:
- diffcyt: `REFERENCE_LEVEL=unstimulated`, `BLOCK_COLUMN=batch`.
- batch-assess and CytoNorm: `REFERENCE_COLUMN=control`, `REFERENCE_VALUES=tcu1`.
- cyCombine: `COVARIATE_COLUMN=condition`.

## Platform features exercised

- Named, linked ports with subfolder placement.
- Links that skip levels: prep's metadata goes to every step.
- A fan-out / fan-in DAG.
- The same app three times in one workflow.
- Several links into one input port.
- R and Python apps side by side, with Lambda-capable steps next to Fargate steps.
- A workflow interface whose outputs are bound to dataset folders at run time.
- Results that render in the Pennsieve viewer: HTML, CSV and FCS.

## Demo data

The CytoBatchFlagR spectral flow cytometry dataset.

> Koenig Z, Andorf S, Tilburgs T, Eswar S. *CytoBatchFlagR: Spectral flow cytometry dataset.* Zenodo (2025).
> https://doi.org/10.5281/zenodo.15388817. Licensed CC BY 4.0.

- **Sample:** healthy adult peripheral blood leukocytes, Cytek Aurora, 28 markers, pre-gated to CD45+CD14− live single cells.
- **Design:** 18 batches, each holding the same unstimulated replicate controls (tcu1/tcu2, one donor) and two stimulated samples (tcs3/tcs4: anti-CD3/CD28 + IL-2 for 7 days, two other donors).
- **Used here:** batches 01–06, 24 files, 10.2 M events, 1.46 GB.
- **Method paper:** the batch assessment method behind the dataset is Eswar et al. (2026).

Fetch it with:

```
scripts/fetch-sample-data.sh                   # batches 01-06 into data/zenodo-15388817/
scripts/fetch-sample-data.sh data/all all      # all 18 batches (72 files, 3.7 GB)
```

The script checks every file's MD5 against the Zenodo record. It writes `samples.csv` with the
condition, the control id and the donor, which it reads from each file's `$TUBENAME`.

## Run locally (no Pennsieve account needed)

```
scripts/run-local.sh both data/zenodo-15388817 data/run    # or: a | b
MAX_EVENTS_PER_SAMPLE=20000 scripts/run-local.sh a data/zenodo-15388817 data/quick   # quick run
```

The script builds each app from the sibling `../processor-*` checkouts. It assembles every step's
`INPUT_DIR` from the linked outputs, the way a compute node does, and prints where the reports are.

Regenerate the workflow definitions after changing an app's resources:

```
scripts/build-workflows.py --tag v0.1.0
```

## Citations

- **Background and workflow design**
  - Mathew D, Giles JR, Baxter AE, et al. Deep immune profiling of COVID-19 patients reveals distinct immunotypes with therapeutic implications. *Science* 2020;369(6508):eabc8511. doi:10.1126/science.abc8511. PMID 32669297.
  - Nowicka M, Krieg C, Crowell HL, et al. CyTOF workflow: differential discovery in high-throughput high-dimensional cytometry datasets. *F1000Res* 2017;6:748. doi:10.12688/f1000research.11622.3. PMID 28663787.
  - Quintelier K, Couckuyt A, Emmaneel A, et al. Analyzing high-dimensional cytometry data using FlowSOM. *Nat Protoc* 2021;16(8):3775-3801. doi:10.1038/s41596-021-00550-0. PMID 34172973.
  - Liechti T, Weber LM, Ashhurst TM, et al. An updated guide for the perplexed: cytometry in the high-dimensional era. *Nat Immunol* 2021;22(10):1190-1197. doi:10.1038/s41590-021-01006-z. PMID 34489590.
- **Preparation and quality control**
  - White S, Quinn J, Enzor J, et al. FlowKit: A Python Toolkit for Integrated Manual and Automated Cytometry Analysis Workflows. *Front Immunol* 2021;12:768541. doi:10.3389/fimmu.2021.768541. PMID 34804056.
  - Emmaneel A, Quintelier K, Sichien D, et al. PeacoQC: Peak-based selection of high quality cytometry data. *Cytometry A* 2022;101(4):325-338. doi:10.1002/cyto.a.24501. PMID 34549881.
  - Ionita M, McKeague ML, Painter MM, et al. Cleanet: Robust Doublet Detection in Cytometry Data Based on Protein Expression Patterns. *Cytometry A* 2025;107(11):716-729. doi:10.1002/cyto.a.24961. PMID 41065042.
- **Clustering, embedding and differential testing**
  - Van Gassen S, Callebaut B, Van Helden MJ, et al. FlowSOM: Using self-organizing maps for visualization and interpretation of cytometry data. *Cytometry A* 2015;87(7):636-645. doi:10.1002/cyto.a.22625. PMID 25573116.
  - Becht E, McInnes L, Healy J, et al. Dimensionality reduction for visualizing single-cell data using UMAP. *Nat Biotechnol* 2019;37(1):38-44. doi:10.1038/nbt.4314. PMID 30531897.
  - Weber LM, Nowicka M, Soneson C, Robinson MD. diffcyt: Differential discovery in high-dimensional cytometry via high-resolution clustering. *Commun Biol* 2019;2:183. doi:10.1038/s42003-019-0415-5. PMID 31098416.
- **Batch effects and normalization**
  - Van Gassen S, Gaudilliere B, Angst MS, Saeys Y, Aghaeepour N. CytoNorm: A Normalization Algorithm for Cytometry Data. *Cytometry A* 2020;97(3):268-278. doi:10.1002/cyto.a.23904. PMID 31633883.
  - Quintelier KLA, Willemsen M, Bosteels V, et al. CytoNorm 2.0: A flexible normalization framework for cytometry data without requiring dedicated controls. *Cytometry A* 2025;107(2):69-87. doi:10.1002/cyto.a.24910. PMID 39871681.
  - Pedersen CB, Dam SH, Barnkob MB, et al. cyCombine allows for robust integration of single-cell cytometry datasets within and across technologies. *Nat Commun* 2022;13(1):1698. doi:10.1038/s41467-022-29383-5. PMID 35361793.
  - Orlova DY, Zimmerman N, Meehan S, et al. Earth Mover's Distance (EMD): A True Metric for Comparing Biomarker Expression Levels in Cell Populations. *PLoS One* 2016;11(3):e0151859. doi:10.1371/journal.pone.0151859. PMID 27008164.
  - Eswar S, Koenig ZT, Tursi AR, et al. CytoBatchFlagR: A Comprehensive Framework to Objectively Assess High-Parameter Cytometry Data for Batch Effects. *Cytometry A* 2026;109(4):241-256. doi:10.1002/cyto.a.70024. PMID 41968341.

Each app's README lists the full set for its step, including edgeR, limma, ComBat and flowCore.

## Licence

The workflow definitions, scripts and docs in this repository are Apache-2.0. Each app states its
own licence, and its image includes third-party components under their licences, several of them
GPL or AGPL; each app's `THIRD_PARTY.md` lists them.
