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

Output follows the same rules as the other verbs (writes `tableau.png` by default — CairoMakie also
renders `.svg`/`.pdf`; `output=nothing` returns the Makie `Figure`; `overwrite` guards existing
files).

## Animating over time

With an interactive time dimension, a `tableau` can be **animated**: the whole scene evolves frame
by frame via `Makie.record`. The generic layout is reused — the plotting callbacks draw
`Observable`s that the record loop updates per frame. In practice you drive this through a
data-source method (for PhysiCell simulations, `index=:all` on the simulation method); see
[Movies](@ref) and [Extensions & PhysiCell](@ref).

```@docs
tableau
```
