# tableau for PhysiCell simulations — the CairoMakie + PhysiCellModelManager extension.
#
# Loaded when BOTH CairoMakie and PhysiCellModelManager are present. Implements
# `tableau(::Type{Simulation}, sim_id; …)`: load one snapshot's cells + substrates, build the
# focal (cell scatter) and satellite (substrate heatmap) axis callbacks, and hand them to
# `Montage._tableauFigure` (the layout engine in MontageCairoMakieExt, which is also loaded
# whenever CairoMakie is). DataFrame access uses property/Base functions only — no `using
# DataFrames` needed.

module MontageCairoMakiePCMMExt

using Montage
using CairoMakie
using PhysiCellModelManager

const _SUBSTRATE_META = ("x", "y", "z", "volume")   # substrate DataFrame columns that aren't substrates

# Reshape one substrate column onto its (x, y) voxel grid — robust to voxel ordering.
function _substrateGrid(subs, name::AbstractString)
    x = subs.x; y = subs.y; v = getproperty(subs, Symbol(name))
    xs = sort(unique(x)); ys = sort(unique(y))
    xi = Dict(xv => i for (i, xv) in enumerate(xs))
    yi = Dict(yv => j for (j, yv) in enumerate(ys))
    M = fill(NaN, length(xs), length(ys))
    @inbounds for k in eachindex(v)
        M[xi[x[k]], yi[y[k]]] = v[k]
    end
    return xs, ys, M
end

"""
    tableau(::Type{Simulation}, sim_id; time=:final, substrates=<all>, colormap=:viridis,
            markersize=6, legend=:auto, size=(1000, 1000),
            output=joinpath(dataDir(), "outputs", "tableau.png"), overwrite=false)

Compose one PhysiCell simulation state (CairoMakie + PhysiCellModelManager extension): the
**cell layer re-plotted as a scatter** colored by cell type, centered, with one **substrate
heatmap + colorbar** per substrate auto-arranged around it, all sharing a spatial extent.

- `time` — a single snapshot selector (`:final`/`:initial`/`Integer`, as in `PhysiCellSnapshot`).
- `substrates` — which substrates get satellites (default: all present).
- `colormap`, `markersize`, `size` — heatmap colormap, cell marker size, figure size.
- `legend` — cell-type legend placement: `:auto` (default) an empty grid cell, off the cell
  plot, falling back to an in-axis corner when the grid is full; a position `Symbol`
  (`:rt`, `:lt`, `:rb`, `:lb`, `:ct`, …) an in-axis corner; a grid cell `(row, col)`; or
  `nothing` for none.
- `output` — writes by default (`.png`; CairoMakie also does `.svg`/`.pdf`), erroring if it
  exists unless `overwrite=true`; `output=nothing` returns the Makie `Figure`.

A `Simulation` object or a `PCMMOutput{Simulation}` is also accepted in place of `sim_id`.

# Examples
```julia
using CairoMakie, PhysiCellModelManager, Montage
tableau(Simulation, 1)                                        # cells + every substrate
tableau(Simulation, 1; time=60, substrates=["oxygen"], legend=:rt, output="ox.png")
fig = tableau(Simulation, 1; output=nothing)                  # get the Makie Figure
```
"""
function Montage.tableau(::Type{Simulation}, sim_id::Integer; time = :final,
                         substrates = nothing, colormap = :viridis, markersize::Real = 6,
                         legend = :auto, size = (1000, 1000),
                         output::Union{Nothing,AbstractString} = joinpath(dataDir(), "outputs", "tableau.png"),
                         overwrite::Bool = false)
    snap = PhysiCellSnapshot(sim_id, time; include_cells = true, include_substrates = true, include_mesh = true)
    snap === missing && error("simulation $sim_id has no snapshot at time $(repr(time))")
    cells, subs = snap.cells, snap.substrates

    available = filter(n -> !(n in _SUBSTRATE_META), string.(propertynames(subs)))
    names = isnothing(substrates) ? available : collect(String.(substrates))
    isempty(names) && error("simulation $sim_id has no substrates to plot")
    bad = setdiff(names, available)
    isempty(bad) || error("unknown substrate(s) $(bad); available: $(available)")

    # shared spatial extent from the mesh
    xlims = extrema(snap.mesh["x"])
    ylims = extrema(snap.mesh["y"])

    # focal: cells scattered by type (labeled; the layout engine places the legend)
    focal = function (ax)
        ct = cells.cell_type_name
        for name in sort(unique(ct))
            m = ct .== name
            CairoMakie.scatter!(ax, cells.position_1[m], cells.position_2[m];
                                label = name, markersize = markersize)
        end
        return ax
    end

    # satellites: one heatmap per substrate
    satellites = [
        function (ax)
            xs, ys, M = _substrateGrid(subs, name)
            return CairoMakie.heatmap!(ax, xs, ys, M; colormap = colormap)
        end
        for name in names
    ]

    # delegate layout + output to the generic (data-agnostic) tableau
    return Montage.tableau(focal, satellites;
                           focal_title = "cells (t = $(snap.time))",
                           satellite_titles = names, colorbar_labels = names,
                           xlims = xlims, ylims = ylims, size = size,
                           legend = isempty(cells.cell_type_name) ? nothing : legend,
                           output = output, overwrite = overwrite)
end

# Accept a simulation object or a single-simulation run output.
Montage.tableau(sim::Simulation; kwargs...) = tableau(Simulation, sim.id; kwargs...)
Montage.tableau(out::PCMMOutput{Simulation}; kwargs...) = tableau(Simulation, out.trial.id; kwargs...)

end # module
