# The `tableau` verb: how the heterogeneous parts of one state relate spatially.
#
# A focal panel (the cell layer) with satellite panels (substrate heatmaps + colorbars)
# arranged around it, sharing a spatial extent. Unlike montage/storyboard, tableau can't be
# built by stitching SVGs — it needs a real layout engine, shared axes, and true colorbars,
# i.e. CairoMakie, plotting from data. So it lives entirely in the CairoMakie extensions;
# the core only declares the entry points.

"""
    tableau(args...; kwargs...)

Compose one state as a **focal panel surrounded by satellite panels** — the verb for showing
how the heterogeneous parts of a single state relate spatially (e.g. a cell layer centered
with substrate heatmaps arranged around it, sharing a spatial extent).

Unlike [`montage`](@ref) and [`storyboard`](@ref), `tableau` is **CairoMakie-only and
data-driven** — it re-plots from data rather than stitching SVGs — so it becomes available
only once the CairoMakie extension is loaded (`using CairoMakie`); without it, calling
`tableau` errors with that hint. Two methods are then provided:
- **`tableau(focal, satellites; …)`** — the data-agnostic form (`MontageCairoMakieExt`):
  `focal` and `satellites` are axis callbacks (`ax -> …`); it arranges them and writes the figure.
- **`tableau(::Type{Simulation}, sim_id; …)`** — the PhysiCell convenience form
  (`MontageCairoMakiePCMMExt`, also needs PhysiCellModelManager), which builds those callbacks
  from a simulation's cells + substrates.
"""
tableau(args...; kwargs...) = error(
    "`tableau` needs the CairoMakie extension (and PhysiCellModelManager for simulations) — " *
    "run `using CairoMakie, PhysiCellModelManager`")
