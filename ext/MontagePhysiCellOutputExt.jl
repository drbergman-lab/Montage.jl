# Folder-path PhysiCell support for the SVG verbs (montage, storyboard).
#
# Loaded when PhysiCellOutput is present. Adds methods that dispatch on PhysiCellOutput's
# `PhysiCellSequence` (a whole output folder) and `PhysiCellSnapshot` (one state), so
# PhysiCell users who don't use PCMM can drive the verbs from an output folder — still
# `using Montage`. Only SVG globbing is needed here (no data parsing, no CairoMakie); the
# `PhysiCellSequence`/`PhysiCellSnapshot` instances carry the folder + snapshot metadata.
#
# tableau (data-driven) lives in a separate CairoMakie-gated extension.

module MontagePhysiCellOutputExt

using Montage
using PhysiCellOutput

# state selector → PhysiCell SVG filename
_stateFile(sel::Symbol) = sel in (:initial, :final) ? "$(sel).svg" :
    error("index Symbol must be :initial or :final; got $(repr(sel))")
_stateFile(sel::Integer) = "snapshot" * lpad(Int(sel), 8, '0') * ".svg"

_stateSVG(folder, sel) = joinpath(folder, _stateFile(sel))

# `index` selects a movie when it names a sequence of snapshots.
_isMovieIndex(index) = index === :all || index isa AbstractVector

# Default panel title for a folder: the run directory name (PhysiCell output folders are
# conventionally `<name>/output`, so this is `<name>`).
_folderLabel(folder) = basename(dirname(normpath(folder)))

# --- cell-type legend ---------------------------------------------------------------------
#
# PhysiCell writes `output/legend.svg` alongside the snapshots, and it already carries exactly the
# data a legend needs — one row per *configured* cell type, giving both the name and the colour
# PhysiCell draws it with:
#
#     <circle … fill="grey"/> <circle … fill="grey"/> <text …> tumor_epi </text>
#
# so we parse it for `(label, colour)` pairs and draw the legend ourselves (flat circles + text,
# wrapped, at the title font size). Two consequences worth stating:
#
#   * Cost is one ~1.5 KB file **per simulation**, not per frame. It does not matter how many
#     snapshots a movie has.
#   * The legend describes what the *model can contain*, per the config — deliberately not
#     narrowed to what happens to be visible in a particular snapshot. That is what makes a movie
#     legend correct for every frame without inspecting any of them. An explicit `cell_types`
#     filter is different: those cells were removed on purpose, so `_keptLegend` narrows the key
#     to match (a legend advertising types the user just filtered out would be wrong).
#
# Row order is the config's own cell-type order, which is more meaningful than sorting by name.

const _LEGEND_ROW_RE = r"<circle[^>]*\bfill=\"([^\"]*)\"[^>]*/>\s*<circle[^>]*/>\s*<text[^>]*>\s*(.*?)\s*</text>"s

"""The run's `legend.svg`, or `nothing` when it has none (older PhysiCell, some 3-D runs)."""
_legendSVG(folder) = (p = joinpath(folder, "legend.svg"); isfile(p) ? p : nothing)

"""
    _legendRows(legend_svg_text) -> Vector{Tuple{String,String}}

The `(label, colour)` pairs in one PhysiCell `legend.svg`, in the config's cell-type order.
"""
_legendRows(text::AbstractString) =
    [(String(m.captures[2]), String(m.captures[1])) for m in eachmatch(_LEGEND_ROW_RE, text)]

"""
    Montage._cellTypeLegend(folders) -> Vector{Tuple{String,String}}

The `(label, colour)` entries for a composition, from each folder's `legend.svg`, unioned across
folders so a sweep that mixed configs still explains every cell type any panel can contain. Order
follows the config (first folder's order, with later folders' extra types appended).

Empty when no folder has a `legend.svg`, which the core then treats as "no legend".

This implements the core-declared hook so the CairoMakie extensions can reach it too — `tableau`
colours its cells from the same source, keeping a tableau and a montage of one run consistent.
"""
function Montage._cellTypeLegend(folders)
    entries = Tuple{String,String}[]
    seen = Set{String}()
    for folder in folders
        path = _legendSVG(folder)
        path === nothing && continue
        for (label, color) in _legendRows(read(path, String))
            label in seen || (push!(seen, label); push!(entries, (label, color)))
        end
    end
    return entries
end

# --- cell filtering in the stitched SVGs ----------------------------------------------------
#
# PhysiCell tags every cell in its snapshot SVGs:
#
#     <g id="cell442" type="tumor_epi" dead="true"> <circle …/> <circle …/> </g>
#
# so which cells to show can be decided without reading any data — just drop the groups that do
# not match. The `id="cell…"` requirement scopes this to the cells layer on its own: the `tissue`
# wrapper and `ECM` group have other ids, and the time/agent-count text is not a `<g>` at all.
# Cell groups never nest, so a non-greedy match to the first `</g>` is exact.

const _CELL_BLOCK_RE = r"[ \t]*<g\s+id=\"cell\d+\"\s+type=\"([^\"]*)\"\s+dead=\"([^\"]*)\"[^>]*>.*?</g>\n?"s
const _AGENT_COUNT_RE = r"(>\s*)(\d+)(\s+agents\s*<)"

_asNameVector(x::Union{AbstractString,Symbol}) = [String(x)]
_asNameVector(x) = String.(collect(x))

const _CELL_ID_RE = r"id=\"cell(\d+)\""
const _FILL_RE = r"fill=\"[^\"]*\""

"""
    _cellTransform(cell_types, include_dead; recolor=nothing) -> transform

A `Panel` transform (see [`Panel`](@ref)) that edits one snapshot's cell layer: keeps only the
requested cells and, when `recolor` is given, repaints each kept cell from its data. Returns
`identity` when there is nothing to do, so an untouched panel really is untouched.

Filtering and recolouring share one pass because both walk the same cell groups. `recolor` is a
`(values, (lo, hi), colormap)` tuple: `values` maps cell `ID` to the quantity, and `(lo, hi)` is
fixed by the caller across every panel or frame so colours stay comparable.

PhysiCell's own "N agents" label is rewritten to the number actually shown — a figure captioned
`511 agents` while displaying 200 of them would be wrong.
"""
function _cellTransform(cell_types, include_dead::Bool; recolor = nothing)
    cell_types === nothing && include_dead && recolor === nothing && return identity
    keep = cell_types === nothing ? nothing : Set(_asNameVector(cell_types))
    return function (svg::AbstractString)
        seen = 0        # cell groups the pattern recognised at all
        shown = 0       # of those, the ones kept
        missed = 0      # kept, but with no data value to colour by
        out = replace(svg, _CELL_BLOCK_RE => function (block)
            seen += 1
            m = match(_CELL_BLOCK_RE, block)
            type, dead = m.captures[1], m.captures[2] == "true"
            (keep !== nothing && !(type in keep)) && return ""
            (!include_dead && dead) && return ""
            shown += 1
            recolor === nothing && return block
            values, (lo, hi), colormap = recolor
            idm = match(_CELL_ID_RE, block)
            id = idm === nothing ? nothing : parse(Int, idm.captures[1])
            v = id === nothing ? nothing : get(values, id, nothing)
            v === nothing && (missed += 1; return block)      # keep PhysiCell's own colour
            c = _rampColor(colormap, hi == lo ? 0.5 : (v - lo) / (hi - lo))
            return replace(block, _FILL_RE => "fill=\"$c\"")
        end)
        missed > 0 && @warn "no data value for some cells; they keep PhysiCell's colour" cells=missed
        # Only correct the caption if the cell layer was actually recognised. If the pattern
        # matched nothing — a PhysiCell change to attribute order, say — then nothing was filtered
        # either, and rewriting the count to 0 would mislabel a figure still showing every cell.
        seen == 0 && return out
        return replace(out, _AGENT_COUNT_RE => s -> begin
            m = match(_AGENT_COUNT_RE, s)
            m.captures[1] * string(shown) * m.captures[3]
        end)
    end
end

# --- recolouring cells by data ---------------------------------------------------------------
#
# Each cell group carries its id (`id="cell442"`), which joins to the `ID` column of the snapshot's
# cells table — so any column can drive the colour without re-rendering the figure. Only `fill` is
# rewritten: PhysiCell strokes are `stroke-width="0.5"` in a 1000 px canvas, i.e. ~0.15 px once a
# panel is scaled to 300 px, so they are invisible and not worth disturbing.
#
# The colormaps live here, deliberately small, rather than pulling in a colour package or CairoMakie
# — the whole point of this path is that it stays light. `tableau` has Makie's full set.

const _COLORMAPS = Dict(
    :viridis => [(68,1,84), (72,40,120), (62,74,137), (49,104,142), (38,130,142),
                 (31,158,137), (53,183,121), (109,205,89), (253,231,37)],
    :plasma  => [(13,8,135), (84,2,163), (139,10,165), (185,50,137), (219,92,104),
                 (244,136,73), (254,188,43), (240,249,33), (240,249,33)],
    :grays   => [(0,0,0), (32,32,32), (64,64,64), (96,96,96), (128,128,128),
                 (160,160,160), (192,192,192), (224,224,224), (255,255,255)],
)

"""
    _rampColor(colormap, t) -> String

Colour at position `t ∈ [0,1]` along `colormap`, as an SVG `rgb(r,g,b)` string, by linear
interpolation between the ramp's anchor points.
"""
function _rampColor(colormap::Symbol, t::Real)
    anchors = get(_COLORMAPS, colormap, nothing)
    anchors === nothing && error(
        "unknown colormap $(repr(colormap)) for the SVG verbs; this path carries a small built-in " *
        "set $(sort(collect(keys(_COLORMAPS)))) to stay dependency-free. `tableau` has all of " *
        "Makie's colormaps.")
    isfinite(t) || return "grey"
    u = clamp(Float64(t), 0.0, 1.0) * (length(anchors) - 1)
    i = clamp(floor(Int, u) + 1, 1, length(anchors) - 1)
    f = u - (i - 1)
    a, b = anchors[i], anchors[i + 1]
    rgb = ntuple(k -> round(Int, a[k] + f * (b[k] - a[k])), 3)
    return "rgb($(rgb[1]),$(rgb[2]),$(rgb[3]))"
end

"""
    _cellValues(folder, index, column) -> Dict{Int,Float64}

Map each cell's `ID` to its value of `column`, for the state the panel shows. Reads only the cells
table (no substrates, no mesh).
"""
function _cellValues(folder, index, column)
    snap = PhysiCellSnapshot(folder, index; include_cells = true)
    snap === missing && error("could not read cells for snapshot $(repr(index)) in $folder")
    cells = snap.cells
    col = Symbol(column)
    col in propertynames(cells) || error(
        "no cell column $(repr(col)) to color by; call `cellLabels(snapshot)` for the available " *
        "columns")
    vals = getproperty(cells, col)
    # These verbs map a value onto a continuous ramp, so the column has to be numeric. Without this
    # check a categorical column fails as a bare `MethodError` from `Float64("tumor_epi")`.
    eltype(vals) <: Real || error(
        "cannot color by $(repr(col)): its values are $(eltype(vals)), and the SVG verbs map a " *
        "*numeric* column onto a colour ramp. For a categorical column (cell type, phase, …) use " *
        "`tableau`, which draws one labelled series per value.")
    return Dict(Int(i) => Float64(v) for (i, v) in zip(cells.ID, vals))
end

"""
    _svgColorbar(label, lo, hi, colormap; font_size) -> draw function

A horizontal colorbar as a **draw function** `(x, y, avail_w) -> (fragment, w, h)`, the form the
core legend machinery accepts for legends it cannot build itself. Replaces the cell-type key when
cells are coloured by a continuous value, where per-type swatches would mean nothing.

Emitted as one gradient-filled `<rect>` plus flat `<text>` — a single object to nudge in Illustrator
rather than dozens of slices.
"""
function _svgColorbar(label, lo::Real, hi::Real, colormap::Symbol; font_size::Real)
    fmt(v) = string(round(v; sigdigits = 3))
    stops = join(["""<stop offset="$(round(i / 8; digits = 3))" stop-color="$(_rampColor(colormap, i / 8))"/>"""
                  for i in 0:8], "")
    return function (x0::Real, y0::Real, avail_w::Real)
        bar_h = 0.95 * font_size
        tw(t) = 0.58 * font_size * length(t)                 # same estimate the legend layout uses
        lo_s, hi_s, lab = fmt(lo), fmt(hi), string(label)
        gap = 0.4 * font_size
        fixed = tw(lo_s) + tw(hi_s) + tw(lab) + 4gap
        # Shrink the bar to whatever is left rather than holding a floor: core sizes a draw-function
        # legend from what this returns and may put it in a single spare cell, so a hard minimum
        # would overflow into the neighbouring panel. (A label longer than the whole width is a
        # degenerate layout that no clamp here can fix.)
        bar_w = clamp(avail_w - fixed, 0.0, 14 * font_size)
        h = 1.7 * font_size
        cy = y0 + h / 2
        base = cy + 0.35 * font_size                          # text baseline
        x = x0
        io = IOBuffer()
        print(io, """<defs><linearGradient id="montage-cbar" x1="0" y1="0" x2="1" y2="0">$stops</linearGradient></defs>\n""")
        println(io, """<text x="$(Montage._px(x))" y="$(Montage._px(base))" font-family="Arial" font-size="$(Montage._px(font_size))" fill="black">$(Montage._escapeXML(lo_s))</text>""")
        x += tw(lo_s) + gap
        println(io, """<rect x="$(Montage._px(x))" y="$(Montage._px(cy - bar_h / 2))" width="$(Montage._px(bar_w))" height="$(Montage._px(bar_h))" fill="url(#montage-cbar)" stroke="black" stroke-width="1"/>""")
        x += bar_w + gap
        println(io, """<text x="$(Montage._px(x))" y="$(Montage._px(base))" font-family="Arial" font-size="$(Montage._px(font_size))" fill="black">$(Montage._escapeXML(hi_s))</text>""")
        x += tw(hi_s) + 2gap
        println(io, """<text x="$(Montage._px(x))" y="$(Montage._px(base))" font-family="Arial" font-size="$(Montage._px(font_size))" fill="black">$(Montage._escapeXML(lab))</text>""")
        return String(take!(io)), Montage._px(x + tw(lab) - x0), Montage._px(h)
    end
end

"""
    _keptLegend(entries, cell_types) -> entries

Narrow the legend to the cell types actually kept, so a filtered figure's key matches what is on
screen instead of advertising types that were removed. Applies only to a discovered (`:auto`)
legend — an explicit one is the caller's own and is left alone.
"""
_keptLegend(entries, cell_types) =
    cell_types === nothing ? entries :
        filter(e -> e[1] in Set(_asNameVector(cell_types)), entries)

"""
    _resolveAuto(legend, folders) -> legend

Turn `legend=:auto` into real `(label, colour)` entries from the runs' `legend.svg`. Anything else
— explicit entries, a path, or `nothing` — passes straight through, so a caller can override the
content while still using `legend_position` to place it.
"""
_resolveAuto(legend, folders, cell_types = nothing) =
    legend === :auto ? _keptLegend(Montage._cellTypeLegend(folders), cell_types) : legend

"""
    _colorPlan(color, panel_states, cell_types, include_dead, colormap) -> (transforms, colorbar)

Work out how to paint each panel. `panel_states[p]` lists the `(folder, index)` states panel `p`
shows — one for a still, many for a movie panel.

Returns a `Panel` transform per panel (a plain function for a still, a per-frame `Vector` for a
movie) and, when `color` is set, a colorbar draw function to use as the legend.

The value range is pooled over **every** state of **every** panel, so a colour means the same thing
in each panel of a montage and each frame of a movie — ranging panels separately would make them
mutually incomparable, which is the whole point of a montage. It is computed *after* filtering, so
cells that will not be drawn cannot stretch the scale.
"""
function _colorPlan(color, panel_states, cell_types, include_dead, colormap)
    if color === nothing
        tf = _cellTransform(cell_types, include_dead)     # frame-invariant, so one function will do
        return [tf for _ in panel_states], nothing
    end
    keep = cell_types === nothing ? nothing : Set(_asNameVector(cell_types))
    maps = [[_cellValues(f, i, color) for (f, i) in states] for states in panel_states]
    kept = Float64[]
    for (states, ms) in zip(panel_states, maps), ((f, i), vmap) in zip(states, ms)
        types, deads = _cellAttributes(_stateSVG(f, i))
        for (id, v) in vmap
            t = get(types, id, nothing)
            t === nothing && continue                     # not drawn in this snapshot
            (keep !== nothing && !(t in keep)) && continue
            (!include_dead && get(deads, id, false)) && continue
            push!(kept, v)
        end
    end
    isempty(kept) && error("no cells left to color after filtering")
    rng = (minimum(kept), maximum(kept))
    cm = Symbol(colormap)
    mk(m) = _cellTransform(cell_types, include_dead; recolor = (m, rng, cm))
    transforms = [length(ms) == 1 ? mk(ms[1]) : map(mk, ms) for ms in maps]
    return transforms, _svgColorbar(color, rng[1], rng[2], cm; font_size = Montage._TITLE_FONT_SIZE)
end

"""
    _cellAttributes(svg_path) -> (Dict(id => type), Dict(id => dead))

Each cell's type and dead flag, read from the snapshot SVG itself — used to apply the same filter to
the value range that the drawing will apply to the cells.
"""
function _cellAttributes(svg_path)
    types = Dict{Int,String}()
    deads = Dict{Int,Bool}()
    isfile(svg_path) || return types, deads
    for m in eachmatch(r"<g\s+id=\"cell(\d+)\"\s+type=\"([^\"]*)\"\s+dead=\"([^\"]*)\"", read(svg_path, String))
        id = parse(Int, m.captures[1])
        types[id] = String(m.captures[2])
        deads[id] = m.captures[3] == "true"
    end
    return types, deads
end

# --- montage -----------------------------------------------------------------------------

"""
    montage(seqs::AbstractVector{<:PhysiCellSequence}; index=:final, title=(<run name>), kwargs...)
    montage(seq::PhysiCellSequence; …)
    montage(snaps::AbstractVector{<:PhysiCellSnapshot}; …)

Compose a montage across PhysiCell output folders (PhysiCellOutput extension). Like
`montage(::Type{Simulation}, …)`, the `index` value decides still vs. movie: a single
`:final`/`:initial`/`Integer` → a still grid of that state; `:all` or a vector/range of
snapshot indices → a movie (each panel's snapshot series, in lockstep). `title` is a
function of the `PhysiCellSequence`.

A **cell-type legend is included by default** (`legend=:auto`), built from each run's
`output/legend.svg` — which lists every cell type the *config* defines, with PhysiCell's own
colours — and drawn as flat circles and labels. It goes in the free cells trailing the last row
when the grid has some (costing no space), else in a band below. Pass `legend=nothing` to suppress it,
`legend=[("label", "red"), …]` to give your own entries, or `legend="path.svg"` to nest a hand-made
file — and `legend_position` (`:auto`, `:bottom`, `:top`, `(row, col)`) to place whichever of those
you chose. In a movie the legend is drawn into every frame.

`cell_types` (a name or vector of names) and `include_dead=false` restrict which cells are drawn,
by dropping the non-matching cell groups from each snapshot SVG — no re-rendering, and PhysiCell's
"N agents" label is corrected to the number actually shown. A `legend=:auto` legend narrows to the
kept types; an explicit `legend` — your own entries, or a file — is used exactly as given.

All other keywords pass through to the core verb (`output`, `overwrite`, `panel_width`,
`framerate`, …).
"""
function Montage.montage(seqs::AbstractVector{<:PhysiCellSequence};
                         index = :final, title = seq -> _folderLabel(seq.folder),
                         legend = :auto, cell_types = nothing, include_dead::Bool = true,
                         color = nothing, colormap = :viridis, kwargs...)
    if _isMovieIndex(index)
        states = [[(seq.folder, i) for i in _frameIndices(seq, index)] for seq in seqs]
        tfs, cbar = _colorPlan(color, states, cell_types, include_dead, colormap)
        panels = [Panel(_frameSVGs(seq, index); title = title(seq), transform = tf)
                  for (seq, tf) in zip(seqs, tfs)]
        return montage(panels; legend = _legendFor(legend, cbar, (s.folder for s in seqs), cell_types),
                       kwargs...)
    end
    fname = _stateFile(index)
    kept = PhysiCellSequence[]
    for seq in seqs
        isfile(joinpath(seq.folder, fname)) ? push!(kept, seq) :
            @warn "no $fname in $(seq.folder); skipping"
    end
    isempty(kept) && error("no $fname found in the given folders")
    states = [[(seq.folder, index)] for seq in kept]
    tfs, cbar = _colorPlan(color, states, cell_types, include_dead, colormap)
    panels = [Panel(joinpath(seq.folder, fname); title = title(seq), transform = tf)
              for (seq, tf) in zip(kept, tfs)]
    return montage(panels; legend = _legendFor(legend, cbar, (s.folder for s in kept), cell_types),
                   kwargs...)
end

Montage.montage(seq::PhysiCellSequence; kwargs...) = montage([seq]; kwargs...)

# A vector of already-selected states → a still grid (one panel per snapshot).
function Montage.montage(snaps::AbstractVector{<:PhysiCellSnapshot};
                         title = snap -> _folderLabel(snap.folder),
                         legend = :auto, cell_types = nothing, include_dead::Bool = true,
                         color = nothing, colormap = :viridis, kwargs...)
    states = [[(s.folder, s.index)] for s in snaps]
    tfs, cbar = _colorPlan(color, states, cell_types, include_dead, colormap)
    panels = [Panel(_stateSVG(s.folder, s.index); title = title(s), transform = tf)
              for (s, tf) in zip(snaps, tfs)]
    return montage(panels; legend = _legendFor(legend, cbar, (s.folder for s in snaps), cell_types),
                   kwargs...)
end
Montage.montage(snap::PhysiCellSnapshot; kwargs...) = montage([snap]; kwargs...)

# Snapshot indices a movie will play, and the SVG paths for them.
_frameIndices(seq::PhysiCellSequence, index) =
    index === :all ? [s.index for s in seq.snapshots] : collect(index)
_frameSVGs(seq::PhysiCellSequence, index) =
    [_stateSVG(seq.folder, i) for i in _frameIndices(seq, index)]

"""
    _legendFor(legend, colorbar, folders, cell_types) -> legend

Pick the legend. When cells are recoloured by data, `:auto` becomes the **colorbar** — a cell-type
key would describe colours the figure no longer uses. Otherwise `:auto` resolves to the cell types
as before, and an explicit `legend` always wins.
"""
_legendFor(legend, colorbar, folders, cell_types) =
    legend === :auto && colorbar !== nothing ? colorbar :
        _resolveAuto(legend, folders, cell_types)

# --- storyboard --------------------------------------------------------------------------

# n evenly-spaced snapshots (from those present), spanning the run.
function _evenSnapshots(seq::PhysiCellSequence, n::Integer)
    n >= 1 || error("n_snapshots must be ≥ 1; got $n")
    snaps = seq.snapshots
    isempty(snaps) && error("no snapshots in $(seq.folder)")
    n >= length(snaps) && return snaps
    return snaps[round.(Int, range(1, length(snaps); length = n))]
end

_snapshotFor(seq::PhysiCellSequence, sel::Symbol) =
    sel === :initial ? first(seq.snapshots) :
    sel === :final ? last(seq.snapshots) :
    error("index Symbol must be :initial or :final; got $(repr(sel))")
function _snapshotFor(seq::PhysiCellSequence, sel::Integer)
    i = findfirst(s -> s.index == sel, seq.snapshots)
    isnothing(i) ? error("no snapshot $sel in $(seq.folder)") : seq.snapshots[i]
end

"""
    storyboard(seq::PhysiCellSequence; index=nothing, n_snapshots=…, title=(t -> "t = \$t"),
               ncols=nothing, kwargs...)

A static filmstrip of one PhysiCell output folder over time (PhysiCellOutput extension).
Timepoints via `index` (a vector of snapshot indices and/or `:initial`/`:final`) or
`n_snapshots` (default 4, evenly spaced incl. endpoints). Frame titles are the snapshot
times through `title`.

`cell_types` and `include_dead` restrict which cells are drawn, as in `montage`.

A **cell-type legend is included by default** (`legend=:auto`), from the run's `output/legend.svg`,
narrowed to the kept cell types (an explicit `legend` is used as given). Since a filmstrip is a
single row with no spare cell, it lands in a band below; pass
`legend=nothing` to suppress it. See `montage` for the other `legend` forms.
"""
function Montage.storyboard(seq::PhysiCellSequence;
                            index = nothing,
                            n_snapshots::Integer = isnothing(index) ? 4 : length(index),
                            title = t -> "t = $t",
                            legend = :auto, cell_types = nothing, include_dead::Bool = true,
                            color = nothing, colormap = :viridis,
                            ncols::Union{Nothing,Integer} = nothing, kwargs...)
    isnothing(index) || n_snapshots == length(index) ||
        error("pass either `index` or `n_snapshots`, not both with different lengths (got n_snapshots=$n_snapshots, length(index)=$(length(index)))")
    snaps = isnothing(index) ? _evenSnapshots(seq, n_snapshots) : [_snapshotFor(seq, sel) for sel in index]
    states = [[(s.folder, s.index)] for s in snaps]
    tfs, cbar = _colorPlan(color, states, cell_types, include_dead, colormap)
    panels = [Panel(_stateSVG(s.folder, s.index); title = string(title(s.time)), transform = tf)
              for (s, tf) in zip(snaps, tfs)]
    return storyboard(panels; ncols = something(ncols, length(panels)),
                      legend = _legendFor(legend, cbar, (seq.folder,), cell_types), kwargs...)
end

end # module
