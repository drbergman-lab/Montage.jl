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
- **`storyboard`** — e.g. one simulation's time course as an ordered strip, or as a movie.
- **`tableau`** — e.g. one simulation at one time: the cell layer centered, each substrate's heatmap (with colorbar) arranged around it, all sharing a spatial extent.

**Movies** (a headline feature) are the animated form of any verb: a `storyboard` movie plays one simulation over time; a `montage` movie animates every panel through time simultaneously to compare dynamics across simulations; a `tableau` movie animates the whole composed scene together.

## Intended usage (subject to change — see [open decisions](PRD.md#open-decisions-to-confirm-with-the-user-before-substantial-implementation))

```julia
using Montage

# Generic core — you supply panels (titles + images, or plotting callbacks + data)
montage(panels; output="grid.svg")
```

With [PhysiCellModelManager.jl](https://github.com/drbergman-lab/PhysiCellModelManager.jl) loaded, a package **extension** adds convenience methods that resolve simulation ids to files/data for you:

```julia
using PhysiCellModelManager, Montage

montage(Simulation)                                   # final state of every simulation, gridded
storyboard(Simulation, 32; movie="sim32.mp4", framerate=15)
tableau(Simulation, 32; time=:final)                  # cells centered, substrate heatmaps around
```

The core never depends on PhysiCellModelManager — install and use Montage on generic image/data inputs without it; the PCMM methods appear automatically when PCMM is present.

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
- [x] Core test suite — SVG-backend verbs on hand-written SVGs; no PCMM, no CairoMakie

### Planned

- [ ] `Project.toml` deps + `[weakdeps]`/`[extensions]` wiring (CairoMakie stack; PCMM weakdep) and `ext/` directory
- [ ] `storyboard` (core) — ordered frame sequence, static and movie
- [ ] `tableau` (core) — focal + satellite scene via CairoMakie `GridLayout` with colorbars
- [ ] Movies — `record(spec, path)`, `Makie.record`-driven animation for all three verbs
- [ ] PCMM extension — `::Type{Simulation}` convenience methods (`montage`/`storyboard`/`tableau`)

Several **open design decisions** gate this work — see [PRD.md](PRD.md#open-decisions-to-confirm-with-the-user-before-substantial-implementation).
