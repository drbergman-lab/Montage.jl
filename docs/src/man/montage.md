```@meta
CurrentModule = Montage
```

# Montage

[`montage`](@ref) arranges a collection of homogeneous panels into a **uniform titled grid** —
the verb for comparing like-for-like across many things (e.g. the final state of every run in a
batch, side by side).

## Panels

A composition is a vector of [`Panel`](@ref)s. A panel carries its content and an optional
title:

```julia
using Montage

panels = [Panel("a/final.svg"; title="A"),
          Panel("b/final.svg"; title="B"),
          Panel("c/final.svg"; title="C")]
montage(panels)
```

For the default `:svg` backend, a panel's content is a **path to an SVG file** — each is inlined
and scaled to fit its cell (losslessly, as vector graphics). You can also pass a loose vector of
raw contents and they are wrapped as untitled panels:

```julia
montage(["a/final.svg", "b/final.svg"])   # untitled
```

## The grid

Panels are laid out row-major in a `ceil(sqrt(n))`-column grid, with uniform cells sized from the
largest panel aspect ratio so nothing clips. A title band is reserved for the whole grid only if
at least one panel is titled — an all-untitled montage wastes no vertical space. Tune the geometry
with `panel_width`, `title_height`, and `pad`.

## Output

Like every verb, `montage` **writes by default** (to `montage.svg` in the working directory) and
also returns the composed SVG string:

```julia
montage(panels)                       # writes ./montage.svg, returns the SVG string
montage(panels; output="grid.svg")    # choose the path
montage(panels; output=nothing)       # return the string, write nothing
```

Writing errors if the target exists unless you pass `overwrite=true`.

## Comparing dynamics

If a panel's content is a **vector of frame paths** (one per timepoint) instead of a single path,
`montage` becomes a *montage of movies*: every panel animates through its frames in lockstep. This
needs the movie extension — see [Movies](@ref).

## Choosing which cells appear

For the PhysiCell methods, `cell_types` and `include_dead` restrict which cells are drawn — with no
re-rendering, because PhysiCell tags every cell in its snapshot SVGs with its type and dead flag,
so the non-matching groups are simply dropped:

```julia
montage(Simulation, ids; cell_types = ["tumor_epi", "tumor_mes"])   # tumour only
storyboard(Simulation, 1; include_dead = false)                     # live cells only
```

PhysiCell's own "N agents" caption is rewritten to the number actually shown, and the legend
narrows to the kept types — a figure whose key advertises types you just filtered out would be
misleading.

## Colouring cells by data

`color` names a cells-table column and repaints each cell along `colormap` — again without
re-rendering, by joining each SVG cell group's `id="cell…"` to the `ID` column and rewriting its
fill:

```julia
montage(Simulation, ids; color = :pressure)                 # viridis + a colorbar
storyboard(Simulation, 1; color = :damage, colormap = :plasma)
```

The cell-type legend is replaced by a **colorbar**, since per-type swatches would describe colours
the figure no longer uses. Its range is pooled over every panel (and every frame of a movie) and
computed after any `cell_types`/`include_dead` filtering, so a colour means the same thing
everywhere in the figure — the point of a montage — and excluded cells cannot stretch the scale.

This path carries a small built-in set of colormaps (`:viridis`, `:plasma`, `:grays`) so it stays
dependency-free; [`tableau`](@ref) re-plots through Makie and has the full set.

## Editing panel contents: the `transform` seam

Both of the above are built on a general hook. A [`Panel`](@ref) carries a `transform`, a function
from SVG text to SVG text applied just before the panel is placed:

```julia
montage(["a/final.svg", "b/final.svg"];
        legend = [("mine", "purple")],
        legend_position = :bottom)

# recolour just the first panel, without touching the file on disk
montage([Panel("a/final.svg"; transform = svg -> replace(svg, "fill=\"red\"" => "fill=\"purple\"")),
         Panel("b/final.svg")])
```

The transform runs when a panel is *placed*, so it takes effect only through a verb — constructing a
`Panel` on its own does nothing.

The default is `identity`, which is free — it returns the very same string object, so an
untransformed composition is byte-identical to one built with no transform support at all.

A **movie** panel's content is a list of frames, and `transform` can match it one-for-one:

```julia
# one function: every frame edited the same way
Panel(frames; transform = svg -> replace(svg, "yellow" => "orange"))

# one function per frame: frame t is edited by transform[t]
Panel(frames; transform = [tint(t) for t in eachindex(frames)])
```

The per-frame form exists because some edits genuinely depend on the timepoint. Dropping a cell type
does not — the same function works for every frame — but colouring cells by a data value does, since
each frame has to be mapped from its own snapshot's values. That is exactly how `color` builds its
movie transforms.

```@docs
montage
Panel
```
