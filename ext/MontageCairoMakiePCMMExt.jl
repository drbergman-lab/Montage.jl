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

# `index` selects a movie when it names a sequence of snapshots.
_isMovieIndex(index) = index === :all || index isa AbstractVector

# Substrate column names for a snapshot, honoring a user `substrates` selection.
function _substrateNames(subs, substrates)
    available = filter(n -> !(n in _SUBSTRATE_META), string.(propertynames(subs)))
    names = isnothing(substrates) ? available : collect(String.(substrates))
    isempty(names) && error("no substrates to plot")
    bad = setdiff(names, available)
    isempty(bad) || error("unknown substrate(s) $(bad); available: $(available)")
    return names
end

# The snapshot indices to animate: `:all` → every snapshot present; else the given iterable.
function _resolveFrames(sim_id::Integer, index)
    index === :all || return collect(index)
    dir = joinpath(trialFolder(Simulation, sim_id), "output")
    files = sort!(filter(f -> occursin(r"^snapshot\d+\.svg$", f), readdir(dir)))
    isempty(files) && error("simulation $sim_id has no snapshots")
    return [parse(Int, match(r"\d+", f).match) for f in files]
end

"""
    tableau(::Type{Simulation}, sim_id; index=:final, substrates=<all>, colormap=:viridis,
            markersize=6, legend=:auto, size=(1000, 1000), framerate=15,
            output=<dataDir()/outputs/tableau.png|.mp4>, overwrite=false)

Compose one PhysiCell simulation state (CairoMakie + PhysiCellModelManager extension): the
**cell layer re-plotted as a scatter** colored by cell type, centered, with one **substrate
heatmap + colorbar** per substrate auto-arranged around it, all sharing a spatial extent.

The `index` value decides still image vs. movie, the same way as `montage`:
- `:final`/`:initial`/an `Integer` (a single `PhysiCellSnapshot` selector) → a **still**;
- `:all` or a vector/range of snapshot indices → a **movie**: the whole scene animated over
  those snapshots via `Makie.record`, with a stable colorscale (each substrate's colorrange is
  fixed to its global min/max across frames) and a stable cell-type legend.

Other kwargs: `substrates` (which get satellites, default all), `colormap`, `markersize`,
`size`, and `framerate` (movies). `output` writes by default — `tableau.png` for a still
(`.svg`/`.pdf` also work) or `tableau.mp4` for a movie — erroring if it exists unless
`overwrite=true`; for a still, `output=nothing` returns the Makie `Figure` (a movie needs a
path). A `Simulation` object or a `PCMMOutput{Simulation}` is also accepted for `sim_id`.

# Examples
```julia
using CairoMakie, PhysiCellModelManager, Montage
tableau(Simulation, 1)                                        # still: cells + every substrate
tableau(Simulation, 1; index=60, substrates=["oxygen"], legend=:rt, output="ox.png")
tableau(Simulation, 1; index=:all, output="tableau.mp4", framerate=15)   # movie over all snapshots
tableau(Simulation, 1; index=0:5:120)                         # movie over a subset
```
"""
function Montage.tableau(::Type{Simulation}, sim_id::Integer; index = :final,
                         substrates = nothing, colormap = :viridis, markersize::Real = 6,
                         legend = :auto, size = (1000, 1000), framerate::Integer = 15,
                         output::Union{Nothing,AbstractString} =
                             joinpath(dataDir(), "outputs", _isMovieIndex(index) ? "tableau.mp4" : "tableau.png"),
                         overwrite::Bool = false)
    _isMovieIndex(index) && return _tableauMovie(sim_id, _resolveFrames(sim_id, index);
                                                 substrates, colormap, markersize, legend,
                                                 size, framerate, output, overwrite)

    # --- still image ---
    snap = PhysiCellSnapshot(sim_id, index; include_cells = true, include_substrates = true, include_mesh = true)
    snap === missing && error("simulation $sim_id has no snapshot at index $(repr(index))")
    cells, subs = snap.cells, snap.substrates
    names = _substrateNames(subs, substrates)
    xlims, ylims = extrema(snap.mesh["x"]), extrema(snap.mesh["y"])

    # focal: cells scattered by type (labeled; the layout engine places the legend)
    focal = function (ax)
        ct = cells.cell_type_name
        for nm in sort(unique(ct))
            m = ct .== nm
            CairoMakie.scatter!(ax, cells.position_1[m], cells.position_2[m]; label = nm, markersize = markersize)
        end
        return ax
    end
    satellites = [
        (ax -> begin
            xs, ys, M = _substrateGrid(subs, nm)
            CairoMakie.heatmap!(ax, xs, ys, M; colormap = colormap)
        end) for nm in names
    ]

    return Montage.tableau(focal, satellites;
                           focal_title = "cells (t = $(snap.time))",
                           satellite_titles = names, colorbar_labels = names,
                           xlims = xlims, ylims = ylims, size = size,
                           legend = isempty(cells.cell_type_name) ? nothing : legend,
                           output = output, overwrite = overwrite)
end

# Animate the tableau over `frames` (snapshot indices) via `Makie.record`. Reuses the generic
# layout by plotting Observables the record loop updates per frame. Colorranges are fixed
# globally per substrate (a stable colorscale); the cell-type set is the union across frames.
function _tableauMovie(sim_id, frames; substrates, colormap, markersize, legend, size, framerate, output, overwrite)
    isempty(frames) && error("no frames to animate")
    output === nothing && error("a tableau movie must be written to a file — pass output=\"…mp4\"")
    Montage._assertWritable(output, overwrite)

    snaps = map(frames) do f
        s = PhysiCellSnapshot(sim_id, f; include_cells = true, include_substrates = true, include_mesh = true)
        s === missing && error("simulation $sim_id has no snapshot at index $(repr(f))")
        s
    end
    names = _substrateNames(snaps[1].substrates, substrates)
    xlims, ylims = extrema(snaps[1].mesh["x"]), extrema(snaps[1].mesh["y"])
    xs, ys, _ = _substrateGrid(snaps[1].substrates, names[1])

    # fixed global colorrange per substrate (stable colorscale across frames)
    cranges = Dict(nm => begin
                       vals = vcat((getproperty(s.substrates, Symbol(nm)) for s in snaps)...)
                       lo, hi = extrema(vals)
                       (lo, lo == hi ? lo + one(lo) : hi)
                   end for nm in names)

    all_types = sort(unique(vcat((s.cells.cell_type_name for s in snaps)...)))

    posobs = Dict(t => CairoMakie.Observable(CairoMakie.Point2f[]) for t in all_types)
    matobs = Dict(nm => CairoMakie.Observable(zeros(length(xs), length(ys))) for nm in names)
    titleobs = CairoMakie.Observable("")
    function _setframe!(k)
        s = snaps[k]
        ct = s.cells.cell_type_name
        for t in all_types
            m = ct .== t
            posobs[t][] = CairoMakie.Point2f.(s.cells.position_1[m], s.cells.position_2[m])
        end
        for nm in names
            _, _, M = _substrateGrid(s.substrates, nm)
            matobs[nm][] = M
        end
        titleobs[] = "cells (t = $(s.time))"
    end
    _setframe!(1)

    focal = function (ax)
        for t in all_types
            CairoMakie.scatter!(ax, posobs[t]; label = t, markersize = markersize)
        end
        return ax
    end
    satellites = [
        (ax -> CairoMakie.heatmap!(ax, xs, ys, matobs[nm]; colormap = colormap, colorrange = cranges[nm]))
        for nm in names
    ]

    fig = Montage.tableau(focal, satellites; focal_title = titleobs,
                          satellite_titles = names, colorbar_labels = names,
                          xlims = xlims, ylims = ylims, size = size,
                          legend = isempty(all_types) ? nothing : legend, output = nothing)

    mkpath(dirname(abspath(String(output))))
    CairoMakie.record(fig, String(output), eachindex(frames); framerate = framerate) do k
        _setframe!(k)
    end
    return output
end

# Accept a simulation object or a single-simulation run output.
Montage.tableau(sim::Simulation; kwargs...) = tableau(Simulation, sim.id; kwargs...)
Montage.tableau(out::PCMMOutput{Simulation}; kwargs...) = tableau(Simulation, out.trial.id; kwargs...)

end # module
