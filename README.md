# Montage

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://drbergman-lab.github.io/Montage.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://drbergman-lab.github.io/Montage.jl/dev/)
[![Build Status](https://github.com/drbergman-lab/Montage.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/drbergman-lab/Montage.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/drbergman-lab/Montage.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/drbergman-lab/Montage.jl)

Compose PhysiCell visualizations into intentionally-structured composite figures — and movies.

> **Status: not yet implemented.** This README describes the intended design. See [Implementation Status](#implementation-status) for what actually exists today, [PRD.md](PRD.md) for the behavioral spec, and [progress.md](progress.md) for design rationale.

## What it does

Montage gives you three verbs for the three distinct things you might want a composite figure to say. Static or animated is a separate choice — any verb can render a still figure or a movie.

| Verb | Use it to… | Looks like |
|------|-----------|-----------|
| `montage` | **compare** like-for-like across many things | uniform grid of equal panels |
| `storyboard` | show **one thing evolving over time** | ordered sequence of frames |
| `tableau` | show how **heterogeneous parts of one state relate** spatially | focal panel + satellite panels |

- **`montage`** — e.g. the final state of every simulation in a batch, side by side.
- **`storyboard`** — e.g. one simulation's time course as an ordered, timestamp-titled strip (a static filmstrip for a poster or paper).
- **`tableau`** — e.g. one simulation at one time: the cell layer centered, each substrate's heatmap (with colorbar) arranged around it, all sharing a spatial extent.

**Movies** (a headline feature): a `montage` movie animates every panel through time simultaneously — compare dynamics across simulations, or play one simulation's own frames; a `tableau` movie animates the whole composed scene together. (`storyboard` is deliberately static — the still filmstrip.)

## Intended usage (subject to change — see [open decisions](PRD.md#open-decisions-to-confirm-with-the-user-before-substantial-implementation))

```julia
using Montage

# Still montage: one image per panel, uniform titled grid → writes montage.svg
montage([Panel("a/final.svg"; title="A"), Panel("b/final.svg"; title="B")]; output="grid.svg")

# Montage of movies: give each panel a frame sequence → one call writes the movie
using Rsvg, Cairo, FFMPEG                              # unlocks the movie extension
montage([Panel(framesA; title="A"), Panel(framesB; title="B")]; output="compare.mp4", framerate=15)
```

With [PhysiCellModelManager.jl](https://github.com/drbergman-lab/PhysiCellModelManager.jl) loaded, a package **extension** adds convenience methods that resolve simulation ids to files for you:

```julia
using PhysiCellModelManager, Montage

# montage: compare across sims. `index` decides still image vs. movie
montage(Simulation, simulationIDs())                              # final state of every sim, gridded + written
montage(Simulation, [1, 2, 3]; index=:initial, output=nothing)   # initial states, returned as a string

# storyboard: one sim's time evolution as a static filmstrip with timestamp titles
storyboard(Simulation, 32)                                       # 4 evenly-spaced frames
storyboard(Simulation, 32; index=[:initial, 30, 60, :final])     # explicit timepoints

# tableau: one state, cells centered with substrate heatmaps around (needs CairoMakie)
using CairoMakie
tableau(Simulation, 32)                                          # still → tableau.png
tableau(Simulation, 32; index=:all, output="tableau.mp4")        # movie: the scene over time

using Rsvg, Cairo, FFMPEG                                         # movie extension
montage(Simulation, [1, 2, 22, 32]; index=:all, output="compare.mp4", framerate=15)  # their movies, in lockstep
```

The core never depends on PhysiCellModelManager or CairoMakie — install and use Montage on generic image inputs without them; the movie extension activates once `Rsvg`, `Cairo`, and `FFMPEG` are loaded, and the PCMM methods will appear when PCMM is present.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/drbergman-lab/Montage.jl")
```

## Implementation Status

> For Claude Code sessions: this section is the authoritative record of what has been built. Update it as features are completed. See [PRD.md](PRD.md) for behavioral specifications and [progress.md](progress.md) for decision rationale.

### Completed

- [x] Core types — `Panel` (content + optional title), backend selector types (`SVGBackend`/`MakieBackend`), loose-input normalization
- [x] SVG string-stitch backend — nested-`<svg>` `viewBox` scaling, parsed (not hardcoded) intrinsic dims, uniform grid from max aspect ratio; ported from the prototype
- [x] `montage` (core) — uniform titled grid on the `:svg` backend; `backend`/`panel_width`/`title_height`/`pad`/`output` kwargs; title band reserved only if any panel is titled; `:makie` errors until CairoMakie is loaded
- [x] `montage` regression — verified against the prototype on the dev project (7-col grid of 40 titled sims, scaled cleanly, no clipping)
- [x] One-call movies — a panel whose content is a frame sequence makes `montage` render a movie directly (writing `.mp4`); `output=nothing` returns a `MontageSpec` for `record` to animate. Frames aligned by index, truncated to shortest
- [x] Movie extension (`MontageMovieExt`, weakdeps `Rsvg`/`Cairo`/`FFMPEG`) — montage-of-movies via SVG-frame + FFMPEG; verified end-to-end on 4 real sims (2×2 grid, 25 frames, panels evolving in lockstep with PhysiCell styling)
- [x] `storyboard` (core) — ordered static filmstrip, single-row default with `ncols` wrap; shares the `_svgGrid` builder with `montage`; rejects animated panels (static only)
- [x] PCMM extension (`MontagePhysiCellModelManagerExt`, weakdep `PhysiCellModelManager`) — `montage(::Type{Simulation}, ids)` (`index` picks still-grid vs. movie) and `storyboard(::Type{Simulation}, sim_id)` (`index` vector or `n_snapshots`; timestamp titles); writes by default with `overwrite` guard; also accepts trial objects / `PCMMOutput`s / vectors directly (resolved to their sims); verified end-to-end on the dev project
- [x] `tableau` — CairoMakie backend: focal cell-scatter centered, satellite substrate heatmaps + colorbars auto-ringed around it, shared spatial extent. `MontageCairoMakieExt` (weakdep `CairoMakie`) is the data-agnostic layout engine + public generic `tableau(focal, satellites)`; `MontageCairoMakiePCMMExt` (weakdeps `CairoMakie` + `PhysiCellModelManager`) adds `tableau(::Type{Simulation}, sim_id)`. Verified end-to-end on the dev project
- [x] `tableau` movies — `index=:all`/vector/range animates the scene over snapshots via `Makie.record` (fixed colorscale per substrate, stable legend, animated `t=…` title); writes `.mp4`. Verified end-to-end on the dev project
- [x] Cell-type legend for `montage`/`storyboard` — entries parsed from each run's `output/legend.svg` (which lists every cell type the *config* defines, with PhysiCell's own colors) and unioned across panels: one small file per simulation, independent of frame count. **Drawn** as flat circles + labels rather than nested as an `<svg>`, so it stays editable in Illustrator/PowerPoint; authored at the panel-title size and wrapped to fit. `:auto` uses the free cells trailing the last row when there are any — costing no space — else a band below. On by default with PhysiCellOutput/PCMM loaded; `legend=nothing` opts out and is byte-identical to before. One fixed legend covers every movie frame. `legend` (content: entries, a path, or `:auto`) and `legend_position` (placement) are orthogonal kwargs
- [x] `tableau` cell selection + colouring — `cell_types`/`include_dead` choose which cells are drawn; `color` colours them by any cells-table column, switching between a labelled-series **legend** (categorical, e.g. the `cell_type_name` default) and a **colorbar** (continuous, e.g. `:pressure`), with `color_mode` to force the choice and `cell_colormap` kept separate from the substrates' `colormap`. The layout engine gained `focal_colorbar_label` so the focal panel can carry its own colorbar. Cells are drawn in **PhysiCell's own colours** (from `legend.svg`, via the core-declared `_cellTypeLegend` hook), so a tableau matches a montage/storyboard of the same run; colours also stay fixed under filtering, and movie colorranges are fixed globally after filtering. Verified end-to-end on the dev project
- [x] Core test suite — SVG-backend verbs (montage, storyboard) + movie spec + legend placement on hand-written SVGs; no heavy deps

### Planned

- [ ] Time-based frame alignment — align movie frames by simulation time (nearest snapshot on a common grid), not just index (see [PRD.md](PRD.md))
