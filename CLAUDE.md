# CLAUDE.md — Montage.jl

## About the User
Assistant professor working on computational modeling of cancer-immune interactions, mechanistic modeling, and agent-based modeling (ABM) frameworks. Montage is a visualization/figure-composition tool in the PhysiCell ecosystem alongside [PhysiCellModelManager.jl](https://github.com/drbergman-lab/PhysiCellModelManager.jl) (PCMM).

## Key Documents — Read These First

| Document | Purpose |
|----------|---------|
| [README.md](README.md) | Project overview + **Implementation Status** (what is built, what remains) |
| [PRD.md](PRD.md) | Behavioral specification for every feature — acceptance criteria and edge cases |
| [progress.md](progress.md) | Session journal: decisions made, approaches rejected, open questions |

Start any feature session by reading the relevant PRD entry and the Implementation Status section of `README.md`. (The package was seeded from an original design brief, `HANDOFF.md`, now removed — PRD.md/progress.md are the living record.)

## Project Overview
Montage.jl composes PhysiCell visualizations into intentionally-structured composite figures — and into **movies**. It provides three composition verbs:

- **`montage`** — compare like-for-like across many things (uniform grid of equal panels; e.g. final states across N simulations).
- **`storyboard`** — show one thing evolving over time (1-D ordered sequence of frames; e.g. time evolution of one simulation).
- **`tableau`** — show how heterogeneous components of one state relate spatially (a focal panel with satellite panels around it; e.g. cell layer centered, substrate heatmaps surrounding it).

Static vs. animated is an **orthogonal axis**: any verb can render a static figure or a movie (`Makie.record`). Movies are a first-class, headline feature.

**Status: not yet implemented.** `src/Montage.jl` is a `module Montage … end` stub. See [PRD.md](PRD.md) for the planned API and [progress.md](progress.md) for the design rationale and open decisions.

## Fixed Constraints (decided — do not relitigate)
1. **Package name is `Montage.jl`; module is `Montage`.** The eponymous `montage` function inside module `Montage` is intentional.
2. **Core must not force any heavy dependency.** Both PhysiCellModelManager (PCMM) *and* CairoMakie are optional, reached only through package extensions (`[weakdeps]` + `[extensions]`). The core operates on generic inputs (image paths / data + a layout spec) and renders via the **SVG string-stitch backend, which is the default and lives in core with no heavy deps**. Extensions can only add methods to functions the core already owns, so the verbs and backend selectors are declared/exported in core first.
   Four extensions (all `[weakdeps]`, never `[deps]`):
   - `ext/MontageMovieExt.jl` (`Rsvg`/`Cairo`/`FFMPEG`) — renders montage-of-movies (`record`) via the SVG-frame + FFMPEG path.
   - `ext/MontagePhysiCellModelManagerExt.jl` (`PCMM`) — `montage`/`storyboard` `::Type{Simulation}` convenience (resolve sim ids to output files).
   - `ext/MontageCairoMakieExt.jl` (`CairoMakie`) — the data-agnostic `tableau` layout engine + public generic `tableau(focal, satellites)`.
   - `ext/MontageCairoMakiePCMMExt.jl` (`CairoMakie` + `PCMM`) — `tableau(::Type{Simulation}, …)`, still + movie (`Makie.record`).
3. **`tableau` is CairoMakie-only** (`GridLayout`, `Colorbar`, `Makie.record` for movies) — available once `using CairoMakie`, else the fallback errors helpfully. **Montage-of-movies** uses the SVG-frame + FFMPEG `record` path, **not** CairoMakie. A `:makie` backend for `montage`/`storyboard` was considered and **declined** (SVG-only); the `backend` kwarg + `MakieBackend` selector still exist as vestigial scaffolding on those verbs.

## Relationship to PCMM
PCMM is an optional, weak dependency reached only through the extension. PCMM uses Plots.jl + RecipesBase, **not** Makie — do not try to reuse PCMM's Plots recipes. Montage brings its own CairoMakie stack independently. When working in this repo, do **not** modify PCMM files; treat PCMM's data primitives (`PhysiCellSnapshot`, `PhysiCellSequence`, etc.) as a read-only boundary.

## Scope
All work must remain strictly inside this repository folder (`~/.julia/dev/Montage/`). Do **not** edit files outside this repo. The prototype at `/Users/dbergman1/Research/GeorgetownR01/scripts/StitchFinalSVGs.jl` and PCMM's source are **read-only references**.

## Git Workflow
Claude Code runs directly on the machine and can run any git operation. The boundaries below keep `main` and anything outward-facing under explicit human control while removing friction from local, reversible work.

**Pre-authorized (no prompt needed):**
- Create and switch feature branches when starting work (`git branch` / `git checkout`). Branch from `main` unless told otherwise; name `feature/<short-desc>`.
- Read-only inspection (`git status`/`diff`/`log`/`show`).
- Delete a feature branch once it has been merged into `main` (do this automatically right after a merge).

**Commit procedure (the gate is *diff review*, not a command confirmation):**
1. When a change is ready, present it for review — a `git diff` and/or a short summary of what changed.
2. Wait for the user to confirm they've reviewed it.
3. Once reviewed, **write the commit message and commit directly** — no need to print a ready-to-run command and wait for a second yes. End messages with the `Co-Authored-By: Claude Opus 4.8` trailer.
- Never commit before the user has reviewed the diff.

**Requires explicit request:**
- **Merging to `main`** — only when the user explicitly asks. `main` is the integration gate. Prefer `--ff-only`. After merging, delete the merged feature branch.

**Never:**
- Modify `main` directly for feature work — branch instead.
- Push or publish without an explicit yes (outward-facing).

## Naming Conventions
Consistent with ModelManager.jl / the PhysiCell ecosystem:
- **Functions:** `camelCase` (e.g., `renderMovie`); the three verbs `montage`/`storyboard`/`tableau` are lowercase single words by design.
- **Internal helpers:** `_camelCase` prefix (e.g., `_nestedSVG`, `_svgDimensions`).
- **Types / Structs:** `PascalCase` (e.g., `Panel`, `Layout`).
- **Files:** `snake_case.jl` for source files.
- **Exported vs internal:** the public verbs are exported from `src/Montage.jl`; internal helpers stay unexported.

## Required Workflow for Any Change
1. Produce a **design brief** in the assistant response **before any code changes**; wait for human approval.
2. On approval: update [PRD.md](PRD.md) with the new/changed feature, and open a new [progress.md](progress.md) entry to log the design process, decisions, and open questions.
3. Create the feature branch (`git branch feature/<desc>`; pre-authorized) and implement there.
4. Update the [README.md](README.md) Implementation Status when a feature is complete.
5. Trim PRD.md and progress.md to reflect the final implementation.
6. When done, present the diff for review; once the user has reviewed it, write the commit message and commit (see **Git Workflow** for the full procedure). Merge to `main` only on explicit request.

**Design brief template:**
```
# Design Brief: [Feature/Refactor Name]
## Motivation      — why this is needed / what it solves
## Scope           — files affected, new files, breaking changes
## Proposed Architecture — current vs proposed, key decisions vs alternatives
## Testing Strategy — unit + integration
## Estimated Effort — LOC, risk level, dependencies
```

## Definition of Done
A feature is complete when **all** are true:
1. **Tests pass:** `julia --project=. -e 'using Pkg; Pkg.test()'` runs green.
2. **Docstrings written:** every exported function has a docstring with description, arguments, return value, and a usage example.
3. **README updated:** Implementation Status marks the feature complete.
4. **PRD reflects reality:** if implementation deviated from the PRD, update the PRD entry.
5. **No regressions.**

## Montage-Specific Guidance
- **Two backends, SVG is the default and lives in core.** (A) SVG string-stitching (the prototype — lossless vector, static only, no real heatmaps/colorbars) is the core default, no heavy deps. (B) CairoMakie (`Figure` + `GridLayout`, real colorbars, shared axes, the only path to movies and `tableau`) lives in the CairoMakie extension. Selected via the `backend` kwarg (default `:svg`).
- **Panels use a typed `Panel`/`Layout` spec** (not bare tuples) — expresses the "intentional structure" framing and unifies SVG-path and Makie-path inputs. Define these in core.
- **Movies use a separate `record(spec, path)` entry point**, not per-verb `movie=` kwargs and never per-verb `_movie`/`_gif` variants: a verb builds a composition spec; `record` animates it (in the CairoMakie extension).
- **Getting PhysiCell visuals into Makie:** rasterize an existing snapshot SVG (`Rsvg`+`Cairo` → matrix → `image!`) when you want PhysiCell's own styling; **re-plot from data** (`heatmap!` substrate voxel grid, `scatter!` cells) for `tableau` and any movie needing real heatmaps. Re-plotting requires the PCMM data layer (extension only).
- **Keep PCMM and CairoMakie out of core test deps.** Core tests exercise the SVG-backend verbs on tiny hand-written SVGs / dummy data.

## Julia Environment Rules
- Always run Julia with `--project=.`
- Preferred test command: `julia --project=. -e 'using Pkg; Pkg.test()'`
- Do not edit `Manifest.toml` or add dependencies without explicit approval. CairoMakie (+ `Rsvg`/`Cairo` for SVG rasterization) and PCMM go in `[weakdeps]` with matching `[extensions]` entries — **not** `[deps]`; the core stays light. Confirm the dep list with the user first.

## Environment Facts
- Julia 1.12.6 in the dev env (extensions need ≥1.9). Template `[compat] julia = "1.10.10"`.
- PCMM v0.3.3, UUID `7582d1aa-5e58-4d65-a123-4418a61a2644`, at `~/.julia/packages/PhysiCellModelManager/pLFnT`.
- Dev project with real data: `/Users/dbergman1/Research/GeorgetownR01` (a Julia project, **not** git) — 34+ sims, each with `final.svg` and 124 snapshots. Real data for every mode.
- PhysiCell `final.svg` intrinsic size is 1000×1070 — **parse it, do not hardcode**.
- Renderers available on the machine: `rsvg-convert`, `qlmanage`, `sips`.

## To-dos
Architecture decisions are resolved (2026-07-21) — see [PRD.md](PRD.md) "Decisions". **All three verbs are built:** `montage` (SVG static + movie-of-movies via `record`), `storyboard` (static filmstrip), and `tableau` (CairoMakie: focal cell-scatter + satellite substrate heatmaps). Extensions: `MontageMovieExt`, `MontagePhysiCellModelManagerExt`, `MontageCairoMakieExt`, `MontageCairoMakiePCMMExt`. See [README.md](README.md) Implementation Status. Remaining:

- **Handoff doc → PCMM session** ([PCMM_DOCS_HANDOFF.md](PCMM_DOCS_HANDOFF.md), untracked/excluded): all three verb sections ready. The maintainer carries it to a PCMM-repo session to add the "Visualizing simulations with Montage" page (PCMM is a read-only boundary here). See [progress.md](progress.md) "Docs locality".
- **Time-based frame alignment** — movie follow-up: align by simulation time (nearest snapshot on a common grid), not just index.
- **`dashboard` (name reserved — future verb).** A *live-updating / interactive* counterpart to `tableau`: the same Observable-driven layout engine (`_tableauFigure`), but driven by a live source rather than a fixed frame loop — e.g. polling a running simulation's output as snapshots land (a monitor), or interactive controls like a time slider (likely an interactive Makie backend: GLMakie/WGLMakie). Keep the split clean: `tableau` = the composed static/movie figure; `dashboard` = the live view. (Decided 2026-07-23 — resolves the `tableau` vs. `dashboard` naming question by making them *different* verbs.)
- **(Decided against)** a `:makie` backend for `montage`/`storyboard` — no added value; those verbs stay SVG-only.

### Planned restructure: `PhysiCellMontage.jl` (non-PCMM PhysiCell support)
**Goal:** support PhysiCell users who don't use PCMM — call the verbs on an **output-folder path** (or several, for multiple sims), not a PCMM `Simulation` id.

**Key realization:** the only PCMM-specific bit in today's extensions is **id → output-folder resolution**. Everything else is PhysiCell (file conventions + data parsing) or generic viz. So there's *one* PhysiCell↔Montage glue with *two* front doors (a `Simulation` id, or a folder path). The real coupling for `tableau` is the **PhysiCell output parser** (cells/substrates), which today lives only in PCMM's `loader.jl`.

**Plan (decide before registering Montage — moving `montage(::Type{Simulation})` out is a breaking change; Montage is unregistered `0.0.1`, so now is cheapest):**
1. **New `PhysiCellMontage.jl` package.** Folder-path is the native front door via a package-owned type — `montage(PhysiCellOutput(path))`, `tableau(PhysiCellOutput.(paths))` (a bare `montage("path"::String)` would be type piracy, so use the wrapper type). PCMM is a **`[weakdeps]` + extension** inside `PhysiCellMontage` that adds the `::Type{Simulation}` id front door (resolve id→folder, then reuse the folder-path logic). So folder-path users never pull the heavy PCMM stack; PCMM users still get the id convenience.
2. **Move Montage's two PCMM-facing extensions into `PhysiCellMontage.jl`** (`MontagePhysiCellModelManagerExt`, `MontageCairoMakiePCMMExt`). Montage.jl reverts to **pure, PhysiCell-free viz** (keeps only `MontageMovieExt`, `MontageCairoMakieExt`). No duplication — the glue is written once, both front doors share it.
3. **Extract a standalone `PhysiCellOutput.jl`** (descriptive name, `PhysiCell*` convention — *not* `PhysiCellDataLoader.jl`, to avoid implying API parity with Python's pcdl; both are just downstream of PhysiCell's output format). It reads a PhysiCell output folder → cells/substrates/mesh. Then folder-path `tableau` needs no PCMM. Ideally PCMM adopts it too (cross-repo, separate effort). **Near-term:** folder-path `montage`/`storyboard` need *zero* parsing (just SVG globbing) — ship those first without any parser; folder-path `tableau` is gated on this reader (reimplement a slim one, or gate behind PCMM interim).
