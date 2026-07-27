# Folder-path tableau — the CairoMakie + PhysiCellOutput extension.
#
# Loaded when both CairoMakie and PhysiCellOutput are present. Holds all the data-driven
# tableau logic (reading cells/substrates, building the scatter/heatmap callbacks, and the
# movie loop), dispatching on PhysiCellOutput's `PhysiCellSnapshot` (a state) and
# `PhysiCellSequence` (a folder). The PCMM extension is a thin adapter that constructs these
# and delegates here. Layout comes from the generic `Montage.tableau(focal, satellites)`.

module MontageCairoMakiePhysiCellOutputExt

using Montage
using CairoMakie
using PhysiCellOutput

const _SUBSTRATE_META = ("x", "y", "z", "volume")

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

_isMovieIndex(index) = index === :all || index isa AbstractVector

function _substrateNames(subs, substrates)
    available = filter(n -> !(n in _SUBSTRATE_META), string.(propertynames(subs)))
    names = isnothing(substrates) ? available : collect(String.(substrates))
    isempty(names) && error("no substrates to plot")
    bad = setdiff(names, available)
    isempty(bad) || error("unknown substrate(s) $(bad); available: $(available)")
    return names
end

# A still tableau from a *loaded* snapshot (cells/substrates/mesh present).
function _tableauStill(snap; substrates, colormap, markersize, legend, size, output, overwrite)
    cells, subs = snap.cells, snap.substrates
    names = _substrateNames(subs, substrates)
    xlims, ylims = extrema(snap.mesh["x"]), extrema(snap.mesh["y"])
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

# Ensure a snapshot carries cell/substrate/mesh data (reload if it was built without them).
_loaded(snap::PhysiCellSnapshot) =
    isempty(snap.cells) ?
        PhysiCellSnapshot(snap.folder, snap.index;
                          include_cells = true, include_substrates = true, include_mesh = true) :
        snap

"""
    tableau(snap::PhysiCellSnapshot; substrates=<all>, colormap=:viridis, markersize=6,
            legend=:auto, size=(1000, 1000), output="tableau.png", overwrite=false)

Still tableau of one PhysiCell state: the cells scattered by type, centered, with a substrate
heatmap + colorbar per substrate around them. Reads the snapshot's data (reloading if the
snapshot was constructed without it).
"""
function Montage.tableau(snap::PhysiCellSnapshot;
                         substrates = nothing, colormap = :viridis, markersize::Real = 6,
                         legend = :auto, size = (1000, 1000),
                         output::Union{Nothing,AbstractString} = "tableau.png", overwrite::Bool = false)
    s = _loaded(snap)
    s === missing && error("could not read snapshot $(repr(snap.index)) in $(snap.folder)")
    return _tableauStill(s; substrates, colormap, markersize, legend, size, output, overwrite)
end

_resolveFrames(seq::PhysiCellSequence, index) = index === :all ? [s.index for s in seq.snapshots] : collect(index)

"""
    tableau(seq::PhysiCellSequence; index=:final, substrates=<all>, colormap=:viridis,
            markersize=6, legend=:auto, size=(1000, 1000), framerate=15,
            output=<tableau.png | tableau.mp4>, overwrite=false)

Tableau of a PhysiCell output folder. `index` decides still vs. movie, as in `montage`:
`:final`/`:initial`/`Integer` → a still of that state; `:all` or a vector/range of snapshot
indices → a movie of the scene over those snapshots (fixed colorscale per substrate, stable
legend). Writes `tableau.png`/`tableau.mp4` by default.
"""
function Montage.tableau(seq::PhysiCellSequence;
                         index = :final, substrates = nothing, colormap = :viridis,
                         markersize::Real = 6, legend = :auto, size = (1000, 1000), framerate::Integer = 15,
                         output::Union{Nothing,AbstractString} = _isMovieIndex(index) ? "tableau.mp4" : "tableau.png",
                         overwrite::Bool = false)
    if _isMovieIndex(index)
        return _tableauMovie(seq.folder, _resolveFrames(seq, index);
                             substrates, colormap, markersize, legend, size, framerate, output, overwrite)
    end
    snap = PhysiCellSnapshot(seq.folder, index; include_cells = true, include_substrates = true, include_mesh = true)
    snap === missing && error("no snapshot at index $(repr(index)) in $(seq.folder)")
    return _tableauStill(snap; substrates, colormap, markersize, legend, size, output, overwrite)
end

# Animate the tableau over `frames` (snapshot indices) via `Makie.record`.
function _tableauMovie(folder, frames; substrates, colormap, markersize, legend, size, framerate, output, overwrite)
    isempty(frames) && error("no frames to animate")
    output === nothing && error("a tableau movie must be written to a file — pass output=\"…mp4\"")
    Montage._assertWritable(output, overwrite)

    snaps = map(frames) do f
        s = PhysiCellSnapshot(folder, f; include_cells = true, include_substrates = true, include_mesh = true)
        s === missing && error("no snapshot at index $(repr(f)) in $folder")
        s
    end
    names = _substrateNames(snaps[1].substrates, substrates)
    xlims, ylims = extrema(snaps[1].mesh["x"]), extrema(snaps[1].mesh["y"])
    xs, ys, _ = _substrateGrid(snaps[1].substrates, names[1])

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

end # module
