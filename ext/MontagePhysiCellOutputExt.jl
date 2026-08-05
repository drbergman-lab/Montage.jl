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
#     narrowed to what happens to be visible in a particular snapshot. That is also what makes a
#     movie legend correct for every frame without inspecting any of them.
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

"""
    _resolveAuto(legend, folders) -> legend

Turn `legend=:auto` into real `(label, colour)` entries from the runs' `legend.svg`. Anything else
— explicit entries, a path, or `nothing` — passes straight through, so a caller can override the
content while still using `legend_position` to place it.
"""
_resolveAuto(legend, folders) =
    legend === :auto ? Montage._cellTypeLegend(folders) : legend

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

All other keywords pass through to the core verb (`output`, `overwrite`, `panel_width`,
`framerate`, …).
"""
function Montage.montage(seqs::AbstractVector{<:PhysiCellSequence};
                         index = :final, title = seq -> _folderLabel(seq.folder),
                         legend = :auto, kwargs...)
    legend = _resolveAuto(legend, (s.folder for s in seqs))
    if _isMovieIndex(index)
        panels = [Panel(_frameSVGs(seq, index); title = title(seq)) for seq in seqs]
        return montage(panels; legend, kwargs...)
    end
    fname = _stateFile(index)
    panels = Panel[]
    for seq in seqs
        svg = joinpath(seq.folder, fname)
        isfile(svg) ? push!(panels, Panel(svg; title = title(seq))) :
            @warn "no $fname in $(seq.folder); skipping"
    end
    isempty(panels) && error("no $fname found in the given folders")
    return montage(panels; legend, kwargs...)
end

Montage.montage(seq::PhysiCellSequence; kwargs...) = montage([seq]; kwargs...)

# A vector of already-selected states → a still grid (one panel per snapshot).
function Montage.montage(snaps::AbstractVector{<:PhysiCellSnapshot};
                         title = snap -> _folderLabel(snap.folder),
                         legend = :auto, kwargs...)
    legend = _resolveAuto(legend, (s.folder for s in snaps))
    panels = [Panel(_stateSVG(s.folder, s.index); title = title(s)) for s in snaps]
    return montage(panels; legend, kwargs...)
end
Montage.montage(snap::PhysiCellSnapshot; kwargs...) = montage([snap]; kwargs...)

# SVG paths for a movie's frames.
function _frameSVGs(seq::PhysiCellSequence, index)
    idxs = index === :all ? [s.index for s in seq.snapshots] : collect(index)
    return [_stateSVG(seq.folder, i) for i in idxs]
end

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

A **cell-type legend is included by default** (`legend=:auto`), from the run's `output/legend.svg`.
Since a filmstrip is a single row with no spare cell, it lands in a band below; pass
`legend=nothing` to suppress it. See `montage` for the other `legend` forms.
"""
function Montage.storyboard(seq::PhysiCellSequence;
                            index = nothing,
                            n_snapshots::Integer = isnothing(index) ? 4 : length(index),
                            title = t -> "t = $t",
                            legend = :auto,
                            ncols::Union{Nothing,Integer} = nothing, kwargs...)
    isnothing(index) || n_snapshots == length(index) ||
        error("pass either `index` or `n_snapshots`, not both with different lengths (got n_snapshots=$n_snapshots, length(index)=$(length(index)))")
    snaps = isnothing(index) ? _evenSnapshots(seq, n_snapshots) : [_snapshotFor(seq, sel) for sel in index]
    panels = [Panel(_stateSVG(s.folder, s.index); title = string(title(s.time))) for s in snaps]
    return storyboard(panels; ncols = something(ncols, length(panels)),
                      legend = _resolveAuto(legend, (seq.folder,)), kwargs...)
end

end # module
