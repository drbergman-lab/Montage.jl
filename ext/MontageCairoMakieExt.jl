# CairoMakie backend for Montage — the generic `tableau` layout engine.
#
# Loaded when CairoMakie is present. Implements the core-declared `Montage._tableauFigure`:
# arrange a focal panel in the center with satellite panels ringed around it, each satellite
# paired with a colorbar, all sharing a spatial extent. Data-agnostic — it takes axis
# callbacks (`ax -> …`); the PhysiCell data → callbacks step lives in MontageCairoMakiePCMMExt.

module MontageCairoMakieExt

using Montage
using CairoMakie

# Grid placement for a focal panel plus `n` satellites: focal centered, satellites ringed
# around it. Returns (nrows, ncols, focal_pos, satellite_positions).
function _ringSlots(n::Integer)
    if n <= 8
        ring = [(1, 2), (3, 2), (2, 1), (2, 3), (1, 1), (1, 3), (3, 1), (3, 3)]  # N,S,W,E, corners
        return 3, 3, (2, 2), ring[1:n]
    end
    g = ceil(Int, sqrt(n + 1))
    focal = ((g + 1) ÷ 2, (g + 1) ÷ 2)
    slots = [(r, c) for r in 1:g for c in 1:g if (r, c) != focal][1:n]
    return g, g, focal, slots
end

# Internal: build the tableau `Figure` (layout only, no output). `focal` draws into the
# centered axis; each `satellites[i]` draws into a ringed axis and returns the plot its
# colorbar reads. All axes share `xlims`/`ylims`. `legend` is handled by `_placeLegend!`.
# `colorbar_ticklabelspace` is forwarded to every `Colorbar` as its `ticklabelspace`.
function _tableauFigure(focal, satellites;
                        focal_title="",                     # String or an Observable (animated)
                        satellite_titles::AbstractVector=String[],
                        colorbar_labels::AbstractVector=String[],
                        focal_colorbar_label=nothing,
                        xlims=nothing, ylims=nothing, size=(1000, 1000),
                        legend=:auto, colorbar_ticklabelspace=CairoMakie.Makie.automatic)
    fig = CairoMakie.Figure(; size = size)
    n = length(satellites)
    nrow, ncol, fpos, spots = _ringSlots(n)

    share!(ax) = (xlims !== nothing && ylims !== nothing) &&
        CairoMakie.limits!(ax, xlims[1], xlims[2], ylims[1], ylims[2])
    label(v, i) = i <= length(v) ? v[i] : ""

    # The focal panel is a bare Axis unless it needs a colorbar of its own, in which case it
    # gets the same Axis-plus-Colorbar GridLayout the satellites use.
    fax = if focal_colorbar_label === nothing
        ax = CairoMakie.Axis(fig[fpos[1], fpos[2]]; title = focal_title, aspect = CairoMakie.DataAspect())
        focal(ax)
        ax
    else
        gl = fig[fpos[1], fpos[2]] = CairoMakie.GridLayout()
        ax = CairoMakie.Axis(gl[1, 1]; title = focal_title, aspect = CairoMakie.DataAspect())
        plt = focal(ax)
        CairoMakie.Colorbar(gl[1, 2], plt; label = focal_colorbar_label,
                            ticklabelspace = colorbar_ticklabelspace)
        ax
    end
    share!(fax)

    for i in 1:n
        r, c = spots[i]
        gl = fig[r, c] = CairoMakie.GridLayout()
        ax = CairoMakie.Axis(gl[1, 1]; title = label(satellite_titles, i), aspect = CairoMakie.DataAspect())
        plt = satellites[i](ax)
        share!(ax)
        CairoMakie.hidedecorations!(ax)   # satellites share the focal's extent; keep them clean
        CairoMakie.Colorbar(gl[1, 2], plt; label = label(colorbar_labels, i),
                            ticklabelspace = colorbar_ticklabelspace)
    end

    _placeLegend!(fig, fax, legend, fpos, spots, nrow, ncol)
    return fig
end

# Nicest empty cell for a legend: the one closest to the focal (an adjacent side if free).
_pickLegendCell(empty, focal) =
    empty[argmin([abs(r - focal[1]) + abs(c - focal[2]) for (r, c) in empty])]

# Build the focal legend from `fax`'s labeled plots, placed per `legend`.
#
# A legend in a grid cell does not tell the grid its width: left to Makie's default it would,
# and its column would then be exactly as wide as the legend while the other columns split
# everything else — a 139 px column of panels beside two of 320 px in a 1000 px figure. Floating
# it keeps the columns equal; a legend wider than its third overflows into the neighbouring cell,
# which a larger `size` cures.
const _FLOATING = (tellwidth = false, tellheight = false)
function _placeLegend!(fig, fax, legend, focal_pos, sat_spots, nrow, ncol)
    (legend === nothing || legend === false) && return
    opaque = (framevisible = true, backgroundcolor = :white)
    if legend isa Tuple                                    # explicit grid cell
        (focal_pos == legend || legend in sat_spots) &&
            @warn "tableau legend cell $legend overlaps the focal/a satellite panel"
        CairoMakie.Legend(fig[legend[1], legend[2]], fax; _FLOATING...)
    elseif legend === :auto
        occupied = Set{Tuple{Int,Int}}((focal_pos, sat_spots...))
        empty = [(r, c) for r in 1:nrow for c in 1:ncol if (r, c) ∉ occupied]
        if isempty(empty)
            CairoMakie.axislegend(fax; opaque...)
        else
            r, c = _pickLegendCell(empty, focal_pos)
            CairoMakie.Legend(fig[r, c], fax; _FLOATING...)
        end
    else                                                   # an axislegend position symbol
        CairoMakie.axislegend(fax; position = legend, opaque...)
    end
    return
end

"""
    tableau(focal, satellites; focal_title="", satellite_titles=[], colorbar_labels=[],
            focal_colorbar_label=nothing, xlims=nothing, ylims=nothing, legend=:auto,
            colorbar_ticklabelspace=automatic, size=(1000, 1000), output="tableau.png",
            overwrite=false)

Data-agnostic tableau (CairoMakie extension): a `focal` panel centered with `satellites`
auto-ringed around it, each satellite paired with a colorbar, all sharing `xlims`/`ylims`.

`focal` is an axis callback `ax -> …`; `satellites` is a vector of callbacks `ax -> plot`,
each **returning the plot** its colorbar reads (e.g. a `heatmap!`). `satellite_titles` and
`colorbar_labels` are parallel to `satellites`. `legend` (built from the focal axis's labeled
plots) is `:auto` (an empty grid cell, else an in-axis corner), a position `Symbol`
(`:rt`, `:lt`, …), a grid cell `(row, col)`, or `nothing`. Writes to `output` by default
(erroring if it exists unless `overwrite=true`); `output=nothing` returns the `Figure`.

Set `focal_colorbar_label` to give the **focal** panel a colorbar too — for a focal plot that
encodes a continuous value rather than discrete categories. `focal` must then return its plot,
the same convention the satellites already follow. Such a plot has no labeled series, so pass
`legend=nothing` alongside it.

`colorbar_ticklabelspace` is every colorbar's `ticklabelspace` (Makie's `automatic` by default:
just wide enough for its tick labels). Give it a fixed width in pixels when drawing a **series of
stills** that must line up — a dashboard frame, a figure panel per timepoint. Each frame's
colorrange is its own, so a frame whose ticks read `1.25×10⁻⁴` needs more room than one whose
ticks read `0.08`, and left automatic that difference pushes every axis in the grid over.

# Example
```julia
using CairoMakie, Montage
tableau(ax -> scatter!(ax, xs, ys),
        [ax -> heatmap!(ax, X, Y, Z)]; satellite_titles=["field"], output="scene.png")
```
"""
function Montage.tableau(focal::Function, satellites::AbstractVector;
                         focal_title="",                    # String or an Observable (animated)
                         satellite_titles::AbstractVector=String[],
                         colorbar_labels::AbstractVector=String[],
                         focal_colorbar_label=nothing,
                         xlims=nothing, ylims=nothing, legend=:auto,
                         colorbar_ticklabelspace=CairoMakie.Makie.automatic, size=(1000, 1000),
                         output::Union{Nothing,AbstractString}="tableau.png", overwrite::Bool=false)
    fig = _tableauFigure(focal, satellites; focal_title, satellite_titles,
                         colorbar_labels, focal_colorbar_label, xlims, ylims, size, legend,
                         colorbar_ticklabelspace)
    output === nothing && return fig
    Montage._assertWritable(output, overwrite)
    mkpath(dirname(abspath(String(output))))
    CairoMakie.save(String(output), fig)
    return output
end

end # module
