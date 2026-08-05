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

## Editing panel contents: the `transform` seam

Both of the above are built on a general hook. A [`Panel`](@ref) carries a `transform`, a function
from SVG text to SVG text applied just before the panel is placed:

```julia
montage(["a/final.svg", "b/final.svg"];
        legend = [("mine", "purple")],
        legend_position = :bottom)

# recolour one panel without touching the file on disk
Panel("a/final.svg"; transform = svg -> replace(svg, "fill=\"red\"" => "fill=\"purple\""))
```

The default is `identity`, which is free — it returns the very same string object, so an
untransformed composition is byte-identical to one built with no transform support at all. For a
movie panel, `transform` may instead be a `Vector` parallel to the frames, when the edit differs
per timepoint.

```@docs
montage
Panel
```
