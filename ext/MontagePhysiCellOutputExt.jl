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

# --- montage -----------------------------------------------------------------------------

"""
    montage(seqs::AbstractVector{<:PhysiCellSequence}; index=:final, title=(<run name>), kwargs...)
    montage(seq::PhysiCellSequence; …)
    montage(snaps::AbstractVector{<:PhysiCellSnapshot}; …)

Compose a montage across PhysiCell output folders (PhysiCellOutput extension). Like
`montage(::Type{Simulation}, …)`, the `index` value decides still vs. movie: a single
`:final`/`:initial`/`Integer` → a still grid of that state; `:all` or a vector/range of
snapshot indices → a movie (each panel's snapshot series, in lockstep). `title` is a
function of the `PhysiCellSequence`. All other keywords pass through to the core verb
(`output`, `overwrite`, `panel_width`, `framerate`, …).
"""
function Montage.montage(seqs::AbstractVector{<:PhysiCellSequence};
                         index = :final, title = seq -> _folderLabel(seq.folder), kwargs...)
    if _isMovieIndex(index)
        panels = [Panel(_frameSVGs(seq, index); title = title(seq)) for seq in seqs]
        return montage(panels; kwargs...)
    end
    fname = _stateFile(index)
    panels = Panel[]
    for seq in seqs
        svg = joinpath(seq.folder, fname)
        isfile(svg) ? push!(panels, Panel(svg; title = title(seq))) :
            @warn "no $fname in $(seq.folder); skipping"
    end
    isempty(panels) && error("no $fname found in the given folders")
    return montage(panels; kwargs...)
end

Montage.montage(seq::PhysiCellSequence; kwargs...) = montage([seq]; kwargs...)

# A vector of already-selected states → a still grid (one panel per snapshot).
function Montage.montage(snaps::AbstractVector{<:PhysiCellSnapshot};
                         title = snap -> _folderLabel(snap.folder), kwargs...)
    panels = [Panel(_stateSVG(s.folder, s.index); title = title(s)) for s in snaps]
    return montage(panels; kwargs...)
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
"""
function Montage.storyboard(seq::PhysiCellSequence;
                            index = nothing,
                            n_snapshots::Integer = isnothing(index) ? 4 : length(index),
                            title = t -> "t = $t",
                            ncols::Union{Nothing,Integer} = nothing, kwargs...)
    isnothing(index) || n_snapshots == length(index) ||
        error("pass either `index` or `n_snapshots`, not both with different lengths (got n_snapshots=$n_snapshots, length(index)=$(length(index)))")
    snaps = isnothing(index) ? _evenSnapshots(seq, n_snapshots) : [_snapshotFor(seq, sel) for sel in index]
    panels = [Panel(_stateSVG(s.folder, s.index); title = string(title(s.time))) for s in snaps]
    return storyboard(panels; ncols = something(ncols, length(panels)), kwargs...)
end

end # module
