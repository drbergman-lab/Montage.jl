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

# --- cell selection and colouring -----------------------------------------------------------
#
# The focal panel plots one point per cell. Two things are configurable:
#
#   * which cells appear   — `cell_types` (by name) and `include_dead`
#   * what colour encodes  — `color`, any column of the cells table
#
# Colouring splits into two visual modes, because they need different keys. A *categorical*
# column becomes one labelled scatter series per value plus a Legend (this is the
# `cell_type_name` default, i.e. the original behaviour); a *continuous* column becomes a single
# scatter with a colormap plus a Colorbar. `color_mode` forces the choice for numeric-but-discrete
# columns such as `current_phase`, which look wrong on a continuous ramp.

"""Cell types the model defines, per the snapshot's config — not just those currently alive."""
_configuredTypes(snap) = sort!(collect(values(PhysiCellOutput.cellTypeToNameDict(snap))))

_asNameVector(x::Union{AbstractString,Symbol}) = [String(x)]
_asNameVector(x) = String.(collect(x))

"""
    _cellMask(cells, cell_types, include_dead, snap) -> BitVector

Which cells to plot. `cell_types=nothing` keeps every type; otherwise names are validated
against the **config's** full type list, so selecting a type that happens to be absent from this
snapshot is not an error. `include_dead=false` drops cells flagged dead.
"""
function _cellMask(cells, cell_types, include_dead::Bool, snap)
    types = cells.cell_type_name
    mask = trues(length(types))
    if cell_types !== nothing
        want = _asNameVector(cell_types)
        known = _configuredTypes(snap)
        bad = setdiff(want, known)
        isempty(bad) || error("unknown cell type(s) $(bad); this model defines $(known)")
        keep = Set(want)
        mask .&= [t in keep for t in types]
    end
    if !include_dead
        :dead in propertynames(cells) ?
            (mask .&= .!cells.dead) :
            @warn "include_dead=false but the cells table has no `dead` column; keeping all cells"
    end
    return mask
end

# Categorical unless the column is numeric; `color_mode` overrides. Strings and Bools are always
# categorical (this covers the `cell_type_name` default and `dead`).
function _isCategorical(vals, color_mode::Symbol)
    color_mode === :categorical && return true
    color_mode === :continuous && return false
    color_mode === :auto ||
        error("color_mode must be :auto, :categorical, or :continuous; got $(repr(color_mode))")
    return !(eltype(vals) <: Real) || eltype(vals) <: Bool
end

"""
    _colorColumn(cells, color) -> Symbol

Resolve and validate the `color` keyword against the cells table. The table has ~130 columns, so
the error points at the function that lists them rather than dumping them.
"""
function _colorColumn(cells, color)
    col = Symbol(color)
    col in propertynames(cells) || error(
        "no cell column $(repr(col)) to color by; call `cellLabels(snapshot)` for the available " *
        "columns (plus `cell_type_name`)")
    return col
end

# A range that Makie will accept even when the data is constant.
_safeRange(vals) = (lo = minimum(vals); hi = maximum(vals); (lo, lo == hi ? lo + one(lo) : hi))

"""
    _paletteOrder(cells, col, snap) -> Vector{String}

The value order that fixes which palette slot each category gets. Taken from the **unfiltered**
column — and, when colouring by cell type, unioned with the config's full type list — so that
filtering to a subset, or a type dying out, never reshuffles colours. Without this, `caf` would be
the third series (and third colour) in a full plot but the first in
`cell_types=["caf","nk"]`, making the two figures impossible to compare.
"""
function _paletteOrder(cells, col::Symbol, snap)
    present = unique(string.(getproperty(cells, col)))
    col === :cell_type_name && return sort!(union(_configuredTypes(snap), present))
    return sort!(present)
end

"""
    _physiCellColors(folder) -> Dict{String,String}

Each cell type's **own PhysiCell colour**, from the run's `legend.svg` via the core-declared
`Montage._cellTypeLegend` hook. Using these means a `tableau` and a `montage`/`storyboard` of the
same run agree, instead of the tableau inventing Makie-palette colours for types the user already
recognises by colour. Empty when the run has no `legend.svg`, in which case palette slots are used.
"""
_physiCellColors(folder) =
    Dict(String(l) => String(c) for (l, c) in Montage._cellTypeLegend((folder,)))

# PhysiCell writes named colours ("grey") and occasionally `rgb(r,g,b)`. Makie parses names and
# hex itself, so only the functional form needs converting.
function _parseSVGColor(s::AbstractString)
    m = match(r"^rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)$", strip(s))
    m === nothing && return s
    r, g, b = parse.(Int, m.captures)
    return CairoMakie.RGBf(r / 255, g / 255, b / 255)
end

"""
    _seriesColor(pc, order, v)

Colour for the series of category `v`: PhysiCell's own colour when known, else a palette slot
held stable by `order` (never by plotting order — see [`_paletteOrder`](@ref)).
"""
_seriesColor(pc, order, v) = haskey(pc, v) ? _parseSVGColor(pc[v]) :
    CairoMakie.Cycled(something(findfirst(==(v), order), 1))

# PhysiCell colours apply only when the categories *are* cell types.
_physiCellPalette(col::Symbol, folder) =
    col === :cell_type_name ? _physiCellColors(folder) : Dict{String,String}()

function _substrateNames(subs, substrates)
    available = filter(n -> !(n in _SUBSTRATE_META), string.(propertynames(subs)))
    names = isnothing(substrates) ? available : collect(String.(substrates))
    isempty(names) && error("no substrates to plot")
    bad = setdiff(names, available)
    isempty(bad) || error("unknown substrate(s) $(bad); available: $(available)")
    return names
end

# A still tableau from a *loaded* snapshot (cells/substrates/mesh present).
function _tableauStill(snap; substrates, colormap, markersize, legend, size, output, overwrite,
                       color, color_mode, cell_colormap, cell_types, include_dead)
    cells, subs = snap.cells, snap.substrates
    names = _substrateNames(subs, substrates)
    xlims, ylims = extrema(snap.mesh["x"]), extrema(snap.mesh["y"])

    mask = _cellMask(cells, cell_types, include_dead, snap)
    col = _colorColumn(cells, color)
    vals = getproperty(cells, col)[mask]
    xs, ys = cells.position_1[mask], cells.position_2[mask]

    focal, focal_colorbar_label = if _isCategorical(vals, color_mode)
        order = _paletteOrder(cells, col, snap)          # colours fixed regardless of filtering
        pc = _physiCellPalette(col, snap.folder)         # PhysiCell's own colours when available
        svals = string.(vals)
        cb = function (ax)
            for v in sort(unique(svals))
                m = svals .== v
                CairoMakie.scatter!(ax, xs[m], ys[m]; label = v, color = _seriesColor(pc, order, v),
                                    markersize = markersize)
            end
            return ax
        end
        cb, nothing
    else
        crange = _safeRange(vals)
        cb = ax -> CairoMakie.scatter!(ax, xs, ys; color = vals, colormap = cell_colormap,
                                       colorrange = crange, markersize = markersize)
        cb, string(col)
    end

    satellites = [
        (ax -> begin
            gx, gy, M = _substrateGrid(subs, nm)
            CairoMakie.heatmap!(ax, gx, gy, M; colormap = colormap)
        end) for nm in names
    ]
    return Montage.tableau(focal, satellites;
                           focal_title = "cells (t = $(snap.time))",
                           satellite_titles = names, colorbar_labels = names,
                           focal_colorbar_label = focal_colorbar_label,
                           xlims = xlims, ylims = ylims, size = size,
                           # a continuous focal plot has no labelled series for a Legend to read
                           legend = (focal_colorbar_label === nothing && !isempty(vals)) ? legend : nothing,
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
            color=:cell_type_name, color_mode=:auto, cell_colormap=:viridis,
            cell_types=nothing, include_dead=true,
            legend=:auto, size=(1000, 1000), output="tableau.png", overwrite=false)

Still tableau of one PhysiCell state: the cells scattered, centered, with a substrate heatmap +
colorbar per substrate around them. Reads the snapshot's data (reloading if the snapshot was
constructed without it).

`color` picks the cell column that sets the colour — `:cell_type_name` (the default) gives one
labelled series per type plus a legend; a numeric column such as `:pressure` gives a single
scatter with `cell_colormap` plus a colorbar. `color_mode` (`:auto`, `:categorical`,
`:continuous`) overrides that choice for numeric-but-discrete columns like `:current_phase`.
`cell_types` and `include_dead` restrict which cells are drawn. See `cellLabels(snap)` for the
available columns.
"""
function Montage.tableau(snap::PhysiCellSnapshot;
                         substrates = nothing, colormap = :viridis, markersize::Real = 6,
                         color = :cell_type_name, color_mode::Symbol = :auto,
                         cell_colormap = :viridis, cell_types = nothing, include_dead::Bool = true,
                         legend = :auto, size = (1000, 1000),
                         output::Union{Nothing,AbstractString} = "tableau.png", overwrite::Bool = false)
    s = _loaded(snap)
    s === missing && error("could not read snapshot $(repr(snap.index)) in $(snap.folder)")
    return _tableauStill(s; substrates, colormap, markersize, legend, size, output, overwrite,
                         color, color_mode, cell_colormap, cell_types, include_dead)
end

_resolveFrames(seq::PhysiCellSequence, index) = index === :all ? [s.index for s in seq.snapshots] : collect(index)

"""
    tableau(seq::PhysiCellSequence; index=:final, substrates=<all>, colormap=:viridis,
            markersize=6, color=:cell_type_name, color_mode=:auto, cell_colormap=:viridis,
            cell_types=nothing, include_dead=true, legend=:auto, size=(1000, 1000),
            framerate=15, output=<tableau.png | tableau.mp4>, overwrite=false)

Tableau of a PhysiCell output folder. `index` decides still vs. movie, as in `montage`:
`:final`/`:initial`/`Integer` → a still of that state; `:all` or a vector/range of snapshot
indices → a movie of the scene over those snapshots (fixed colorscale per substrate, stable
legend). Writes `tableau.png`/`tableau.mp4` by default.

`color`, `color_mode`, `cell_colormap`, `cell_types` and `include_dead` control the cell layer —
see `tableau(::PhysiCellSnapshot)`. In a movie a continuous `color` gets a **globally fixed**
colorrange (its min/max across every frame, computed after filtering) so the cell colorscale is
comparable frame to frame, exactly as the substrate heatmaps already are.
"""
function Montage.tableau(seq::PhysiCellSequence;
                         index = :final, substrates = nothing, colormap = :viridis,
                         markersize::Real = 6, color = :cell_type_name, color_mode::Symbol = :auto,
                         cell_colormap = :viridis, cell_types = nothing, include_dead::Bool = true,
                         legend = :auto, size = (1000, 1000), framerate::Integer = 15,
                         output::Union{Nothing,AbstractString} = _isMovieIndex(index) ? "tableau.mp4" : "tableau.png",
                         overwrite::Bool = false)
    if _isMovieIndex(index)
        return _tableauMovie(seq.folder, _resolveFrames(seq, index);
                             substrates, colormap, markersize, legend, size, framerate, output,
                             overwrite, color, color_mode, cell_colormap, cell_types, include_dead)
    end
    snap = PhysiCellSnapshot(seq.folder, index; include_cells = true, include_substrates = true, include_mesh = true)
    snap === missing && error("no snapshot at index $(repr(index)) in $(seq.folder)")
    return _tableauStill(snap; substrates, colormap, markersize, legend, size, output, overwrite,
                         color, color_mode, cell_colormap, cell_types, include_dead)
end

# Animate the tableau over `frames` (snapshot indices) via `Makie.record`.
function _tableauMovie(folder, frames; substrates, colormap, markersize, legend, size, framerate,
                       output, overwrite, color, color_mode, cell_colormap, cell_types, include_dead)
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

    cranges = Dict(nm => _safeRange(vcat((getproperty(s.substrates, Symbol(nm)) for s in snaps)...))
                   for nm in names)

    # Resolve the cell selection and colour column once, up front, so the per-frame update is
    # cheap and the colour scale can be fixed globally.
    masks = [_cellMask(s.cells, cell_types, include_dead, s) for s in snaps]
    col = _colorColumn(snaps[1].cells, color)
    allvals = vcat((getproperty(s.cells, col)[m] for (s, m) in zip(snaps, masks))...)
    categorical = _isCategorical(allvals, color_mode)

    matobs = Dict(nm => CairoMakie.Observable(zeros(length(xs), length(ys))) for nm in names)
    titleobs = CairoMakie.Observable("")

    local focal, focal_colorbar_label, setcells!
    if categorical
        # One series per value, over the union across frames, so colours and the legend are stable.
        all_vals = sort(unique(string.(allvals)))
        order = _paletteOrder(snaps[1].cells, col, snaps[1])
        pc = _physiCellPalette(col, folder)
        posobs = Dict(v => CairoMakie.Observable(CairoMakie.Point2f[]) for v in all_vals)
        setcells! = function (s, m)
            v = string.(getproperty(s.cells, col)[m])
            px, py = s.cells.position_1[m], s.cells.position_2[m]
            for val in all_vals
                sel = v .== val
                posobs[val][] = CairoMakie.Point2f.(px[sel], py[sel])
            end
        end
        focal = function (ax)
            for val in all_vals
                CairoMakie.scatter!(ax, posobs[val]; label = val,
                                    color = _seriesColor(pc, order, val), markersize = markersize)
            end
            return ax
        end
        focal_colorbar_label = nothing        # categorical: a Legend keys it, not a Colorbar
    else
        # Positions and colours must stay the same length, so they travel in ONE Observable and
        # are derived from it — updating them separately would transiently mismatch.
        crange = _safeRange(allvals)
        cellobs = CairoMakie.Observable((CairoMakie.Point2f[], Float64[]))
        setcells! = function (s, m)
            cellobs[] = (CairoMakie.Point2f.(s.cells.position_1[m], s.cells.position_2[m]),
                         Float64.(getproperty(s.cells, col)[m]))
        end
        focal = function (ax)
            pos = CairoMakie.lift(first, cellobs)
            cvals = CairoMakie.lift(last, cellobs)
            return CairoMakie.scatter!(ax, pos; color = cvals, colormap = cell_colormap,
                                       colorrange = crange, markersize = markersize)
        end
        focal_colorbar_label = string(col)
    end

    function _setframe!(k)
        s = snaps[k]
        setcells!(s, masks[k])
        for nm in names
            _, _, M = _substrateGrid(s.substrates, nm)
            matobs[nm][] = M
        end
        titleobs[] = "cells (t = $(s.time))"
    end
    _setframe!(1)

    satellites = [
        (ax -> CairoMakie.heatmap!(ax, xs, ys, matobs[nm]; colormap = colormap, colorrange = cranges[nm]))
        for nm in names
    ]

    fig = Montage.tableau(focal, satellites; focal_title = titleobs,
                          satellite_titles = names, colorbar_labels = names,
                          focal_colorbar_label = focal_colorbar_label,
                          xlims = xlims, ylims = ylims, size = size,
                          legend = (focal_colorbar_label === nothing && !isempty(allvals)) ? legend : nothing,
                          output = nothing)

    mkpath(dirname(abspath(String(output))))
    CairoMakie.record(fig, String(output), eachindex(frames); framerate = framerate) do k
        _setframe!(k)
    end
    return output
end

end # module
