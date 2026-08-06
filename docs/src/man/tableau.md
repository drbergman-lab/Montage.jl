```@meta
CurrentModule = Montage
```

# Tableau

[`tableau`](@ref) composes a single state as a **focal panel surrounded by satellite panels** —
the verb for showing how the heterogeneous parts of one state relate spatially (e.g. a focal
scatter centered, with heatmaps of related fields arranged around it, all on a shared extent).

Unlike [`montage`](@ref) and [`storyboard`](@ref), `tableau` is **data-driven** — it re-plots from
data rather than stitching existing SVGs, so it can produce real heatmaps, colorbars, and shared
axes. That requires **CairoMakie**:

```julia
using CairoMakie, Montage
```

Without it loaded, calling `tableau` errors with that hint.

## The generic form

The data-agnostic method takes an axis **callback** for the focal panel and a vector of callbacks
for the satellites (each returns the plot its colorbar reads):

```julia
using CairoMakie, Montage

xs = range(-1, 1; length=40)
Z  = [exp(-(x^2 + y^2)) for x in xs, y in xs]

tableau(ax -> scatter!(ax, randn(50), randn(50); label="points"),
        [ax -> heatmap!(ax, xs, xs, Z)];
        satellite_titles = ["field"], colorbar_labels = ["field"],
        output = "scene.png")
```

Satellites are auto-ringed around the focal panel; each is paired with a colorbar. The cell-type
**legend** is placed by the `legend` keyword: `:auto` (default) drops it in an empty grid cell —
off the focal plot entirely — falling back to an in-axis corner when the grid is full; you can also
pass a position `Symbol` (`:rt`, `:lt`, …), an explicit grid cell `(row, col)`, or `nothing`.

Set `focal_colorbar_label` to give the **focal** panel a colorbar of its own — for a focal plot
encoding a continuous value rather than discrete categories. The focal callback must then return
its plot, the same convention the satellites follow, and there are no labelled series for a legend
to read, so pass `legend=nothing` with it.

Output follows the same rules as the other verbs (writes `tableau.png` by default;
`output=nothing` returns the Makie `Figure`; `overwrite` guards existing files).

## Vector output

The file extension picks the format — CairoMakie renders `.png`, `.svg` and `.pdf`, so a
publication-ready vector figure is just a different `output`. This applies to every `tableau`
method; the examples below use the PhysiCell one (`using PhysiCellModelManager`):

```julia
tableau(Simulation, 1; output = "figure.pdf")     # vector, for a paper
tableau(Simulation, 1; output = "figure.svg")     # vector, to hand-edit
```

For one cell layer plus a single substrate (511 cells, a 50×50 voxel grid) the three formats come
out very differently:

| format | size | notes |
|---|---:|---|
| `.png` | 154 KB | raster; the default, best for exploring |
| `.pdf` | **52 KB** | vector, and the *smallest* of the three — the natural choice for publication |
| `.svg` | 739 KB | vector, but uncompressed text, so much the largest |

Two caveats worth knowing before reaching for `.svg`:

- **Text is converted to outlines.** CairoMakie's SVG contains no `<text>` elements at all — labels
  become glyph paths — so you cannot retype an axis label in Illustrator. (The stitched verbs,
  [`montage`](@ref) and [`storyboard`](@ref), *do* emit real `<text>`, so their titles and legends
  stay editable. If editable text is what you need, that is the path that gives it.)
- **Heatmaps become one path per voxel.** The bulk of that 739 KB is ~2500 `<path>` elements for a
  50×50 substrate grid, not the cell scatter. A finer mesh or more substrates inflates it quickly.

A tableau **movie** still needs a video container; asking for `.svg` there fails in Makie's
recorder rather than silently producing something odd.

## Choosing which cells appear, and what their colour means

For the PhysiCell methods, the focal cell layer is configurable in two independent ways.

**Which cells** — `cell_types` selects by name (validated against the cell types the *config*
defines, so asking for one that is momentarily absent is not an error), and `include_dead=false`
drops cells flagged dead:

```julia
tableau(Simulation, 1; cell_types = ["nk", "caf"])       # just these two
tableau(Simulation, 1; include_dead = false)             # live cells only
```

**What the colour encodes** — `color` names any column of the cells table (see
`cellLabels(snapshot)` for the ~130 available). The column's type picks the visual mode:

| `color` | mode | key |
|---|---|---|
| `:cell_type_name` (default), or any string/bool column | categorical | one labelled series per value + a **legend** |
| `:pressure`, `:damage`, `:total_volume`, … | continuous | a `cell_colormap` ramp + a **colorbar** |

```julia
tableau(Simulation, 1; color = :pressure)                          # ramp + colorbar
tableau(Simulation, 1; color = :current_phase, color_mode = :categorical)
```

`color_mode` (`:auto`, `:categorical`, `:continuous`) overrides the choice — needed for
numeric-but-discrete columns such as `:current_phase`, which look wrong on a continuous ramp.
Note `cell_colormap` is the *cells'* ramp and is deliberately separate from `colormap`, which
belongs to the substrate heatmaps.

Colours are chosen to make figures comparable with one another:

- **Cells are drawn in PhysiCell's own colours**, read from the run's `legend.svg`. So a `tableau`
  and a `montage`/`storyboard` of the same simulation agree, and the types keep the colours you
  already recognise from PhysiCell's output rather than being reassigned from Makie's palette.
- **Where a colour is not known** (a run without `legend.svg`, or a categorical column that is not
  a cell type), palette slots are used and pinned to the config's cell-type list rather than to
  plotting order — so `caf` keeps the same colour whether you plot every type or filter down to
  `["caf", "nk"]`.
- **In a movie, a continuous `color` gets a globally fixed colorrange** — its min/max across every
  frame, computed *after* filtering — so the scale is comparable frame to frame, exactly as the
  substrate heatmaps already are. This matters more than it sounds: at `t = 0` a quantity like
  pressure is often uniformly zero, which a per-frame scale would render as a meaningless full-range
  spread.

## Animating over time

With an interactive time dimension, a `tableau` can be **animated**: the whole scene evolves frame
by frame via `Makie.record`. The generic layout is reused — the plotting callbacks draw
`Observable`s that the record loop updates per frame. In practice you drive this through a
data-source method (for PhysiCell simulations, `index=:all` on the simulation method); see
[Movies](@ref) and [Extensions & PhysiCell](@ref).

```@docs
tableau
```
