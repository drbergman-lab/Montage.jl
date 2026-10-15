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

Like [`montage`](@ref) and [`storyboard`](@ref), `tableau` lets you set the grid: `ncols` gives
the number of columns (the focal takes the middle cell, the satellites fill the rest in reading
order) and `focal_position=(row, col)` puts the focal in a cell of your choosing. Left alone, the
satellites ring a centered focal.

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
    "`tableau` needs the CairoMakie extension (and PhysiCellOutput or PhysiCellModelManager for simulations) — " *
    "run `using CairoMakie, PhysiCellOutput` or `using CairoMakie, PhysiCellModelManager` first to get it.")

# --- grid arithmetic (core) ---
#
# `tableau` draws with CairoMakie, but *where* its panels go is plain integer arithmetic with no
# Makie in it — the same kind of layout math the core already owns for `_svgGrid`. Keeping it here
# means the one place that decides a tableau's grid is covered by the core test suite, which has
# no CairoMakie; the extension only draws into the cells this returns.

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

# The grid the auto layout would choose, as a column count — what `focal_position` alone lays
# its focal into.
_autoCols(n::Integer) = n <= 8 ? 3 : ceil(Int, sqrt(n + 1))

# A caller-chosen `focal_position`, validated against a grid `nc` columns wide. The row is
# unbounded (more rows are added to reach it); the column is not.
function _focalCell(pos, nc::Integer)
    length(pos) == 2 ||
        error("tableau `focal_position` must be a (row, col) pair; got $(repr(pos))")
    r, c = Int(pos[1]), Int(pos[2])
    (r >= 1 && 1 <= c <= nc) ||
        error("tableau `focal_position` $((r, c)) is outside a grid with $nc column(s)")
    return (r, c)
end

# Neither override given — the auto ring above.
_ringSlots(n::Integer, ::Nothing, ::Nothing) = _ringSlots(n)

# An explicit grid: `ncols` columns (the auto width when only `focal_position` is set), just
# enough rows for the focal plus `n` satellites, focal in the middle cell unless
# `focal_position` names another, satellites filling the remaining cells row-major.
#
# Row-major rather than the N/S/W/E ring: once the grid is the caller's, "the 3rd satellite sits
# in the 3rd free cell, reading order" is the only rule that stays predictable as `ncols` changes.
function _ringSlots(n::Integer, ncols, focal_position)
    nc = ncols === nothing ? _autoCols(n) : Int(ncols)
    nc >= 1 || error("tableau `ncols` must be ≥ 1; got $nc")
    nr0 = cld(n + 1, nc)
    focal = focal_position === nothing ? (cld(nr0, 2), cld(nc, 2)) : _focalCell(focal_position, nc)
    nr = max(nr0, focal[1])                      # a focal pushed past the last row grows the grid
    slots = [(r, c) for r in 1:nr for c in 1:nc if (r, c) != focal][1:n]
    return nr, nc, focal, slots
end
