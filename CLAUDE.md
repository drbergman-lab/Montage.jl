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
   - `ext/MontageCairoMakieExt.jl` — unlocks the Makie backend, `tableau`, and movies (loaded when the user does `using CairoMakie`).
   - `ext/MontagePhysiCellModelManagerExt.jl` — adds `::Type{Simulation}` convenience methods that resolve sim ids to files/data via PCMM.
3. **Movies and `tableau` are built with CairoMakie** (`Makie.record`, `GridLayout`, `Colorbar`) — available only once the CairoMakie extension is loaded. Backend is chosen via a **`backend` kwarg** (default `:svg`); requesting `:makie` (or calling a Makie-only feature) without CairoMakie loaded errors with a message telling the user to `using CairoMakie`.

## Relationship to PCMM
PCMM is an optional, weak dependency reached only through the extension. PCMM uses Plots.jl + RecipesBase, **not** Makie — do not try to reuse PCMM's Plots recipes. Montage brings its own CairoMakie stack independently. When working in this repo, do **not** modify PCMM files; treat PCMM's data primitives (`PhysiCellSnapshot`, `PhysiCellSequence`, etc.) as a read-only boundary.

## Scope
All work must remain strictly inside this repository folder (`~/.julia/dev/Montage/`). Do **not** edit files outside this repo. The prototype at `/Users/dbergman1/Research/GeorgetownR01/scripts/StitchFinalSVGs.jl` and PCMM's source are **read-only references**.

## Git Workflow
Claude Code runs directly on the machine and can run any git operation. **However: never make a commit (or push) without first prompting the user and getting an explicit yes.** Provide the ready-to-run command and let the user confirm.

### Branching Rules
- Never modify `main` directly for feature work.
- Default base branch is `main` unless specified otherwise.
- Branch names: `feature/<short-desc>`.

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
3. Create the feature branch (`git branch feature/<desc>`) and implement there.
4. Update the [README.md](README.md) Implementation Status when a feature is complete.
5. Trim PRD.md and progress.md to reflect the final implementation.
6. When done, output the ready-to-run commit command and **wait for the user to approve before committing**.

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
The core architecture decisions are resolved (2026-07-21) — see [PRD.md](PRD.md) "Decisions". Current plan: build **`montage` (SVG backend) first**, with a typed `Panel`/`Layout` spec and a `backend` kwarg (default `:svg`), then regression-test against the prototype's 34-sim grid before adding `storyboard`/`tableau`/movies. Two decisions remain deferred until their feature is built: the `tableau` layout spec and the default output/non-overwrite naming scheme.
