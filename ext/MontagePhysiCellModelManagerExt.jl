# PCMM convenience methods for Montage.
#
# Loaded when PhysiCellModelManager (PCMM) is present. Adds methods on Montage's own
# `montage` that dispatch on the `Simulation` type, resolving each simulation's output
# SVGs into panels. The `index` value decides the output: a still-image grid (Symbol
# :final/:initial or an Integer snapshot) or a movie (`:all` or a vector/range of snapshot
# indices, rendered via `record`). The added knowledge is the PhysiCell output-file
# convention (`output/final.svg`, `output/snapshotNNNNNNNN.svg`), which is why this keys on PCMM.
#
# `Simulation`, `simulationIDs`, `trialFolder`, and `dataDir` are ModelManager's,
# re-exported by PCMM (`@reexport using ModelManager`), so `using PhysiCellModelManager`
# brings them into scope here.

module MontagePhysiCellModelManagerExt

using Montage
using PhysiCellModelManager

_outputFolder(id::Integer) = joinpath(trialFolder(Simulation, id), "output")

# Single-state SVG filename, matching PCMM's PhysiCellSnapshot `index`: a Symbol
# (:initial/:final) names the state SVG; an Integer selects that indexed snapshot.
function _stateFile(index::Symbol)
    index in (:initial, :final) ||
        error("index Symbol must be :initial or :final; got $(repr(index))")
    return "$(index).svg"
end
_stateFile(index::Integer) = "snapshot" * lpad(Int(index), 8, '0') * ".svg"

# Frame paths for one simulation. `:all` → every snapshotNNNNNNNN.svg present, sorted;
# otherwise `frames` is an iterable of integer snapshot indices.
function _snapshotPaths(id::Integer, frames)
    dir = _outputFolder(id)
    if frames === :all
        files = sort!(filter(f -> occursin(r"^snapshot\d+\.svg$", f), readdir(dir)))
        isempty(files) && error("simulation $id has no snapshot SVGs in $dir")
        return joinpath.(dir, files)
    end
    paths = [joinpath(dir, "snapshot" * lpad(Int(i), 8, '0') * ".svg") for i in frames]
    missing_paths = filter(!isfile, paths)
    isempty(missing_paths) ||
        error("simulation $id is missing snapshot frame(s), e.g. $(basename(first(missing_paths)))")
    return paths
end

# `index` selects a movie when it names a sequence (`:all`, or a vector/range of indices);
# otherwise it selects a single still image.
_isMovieIndex(index) = index === :all || index isa AbstractVector

# Default output path when the caller doesn't pass one — keyed to still vs. movie.
_defaultOutput(index) =
    joinpath(dataDir(), "outputs", _isMovieIndex(index) ? "montage.mp4" : "montage.svg")

"""
    montage(::Type{Simulation}, sim_ids; index=:final, title=(id -> "Sim \$id"),
            panel_width=300, title_height=34, pad=12,
            output=<auto: montage.svg | montage.mp4>, overwrite=false, framerate=15)

Compose a montage from PhysiCell simulations (PCMM extension). Pass the simulation ids
explicitly — e.g. `montage(Simulation, simulationIDs())` to include every simulation.

The `index` value decides still image vs. movie, extending PCMM's `PhysiCellSnapshot`
`index`:

- **Still image** — `index` is `:final`, `:initial` (names the state SVG), or an `Integer`
  (that indexed snapshot, `snapshotNNNNNNNN.svg`): one panel per simulation. Simulations
  missing the file are skipped with a warning. Writes an SVG.
- **Movie** — `index` is `:all` or a vector/range of snapshot indices (e.g. `0:5:120`):
  each panel plays that simulation's snapshot sequence in lockstep (index-aligned,
  truncated to the shortest). Writes a video via [`record`](@ref) — which requires the
  movie extension (`using Rsvg, Cairo, FFMPEG`).

`output` is a path (`AbstractString`) or `nothing`, defaulting to
`dataDir()/outputs/montage.svg` for a still image or `…/montage.mp4` for a movie; it
errors if the file exists unless `overwrite=true`. `output=nothing` returns the in-memory
result instead of writing — the SVG string for a still image, or a [`MontageSpec`](@ref)
for a movie. `framerate` applies to movies.

# Examples
```julia
using PhysiCellModelManager, Montage

montage(Simulation, simulationIDs())                        # final-state grid of every sim
montage(Simulation, [1, 2, 3]; index=:initial)              # initial states of sims 1–3
montage(Simulation, [1, 2, 3]; index=10, output=nothing)    # 10th snapshot, as an SVG string

using Rsvg, Cairo, FFMPEG                                   # movie extension
montage(Simulation, [1, 2, 22, 32]; index=:all, output="compare.mp4", framerate=15)
```
"""
function Montage.montage(::Type{Simulation}, sim_ids;
                         index::Union{Integer,Symbol,AbstractVector{<:Integer}}=:final,
                         title=(id -> "Sim $id"),
                         panel_width::Real=300, title_height::Real=34, pad::Real=12,
                         output::Union{Nothing,AbstractString}=_defaultOutput(index),
                         overwrite::Bool=false, framerate::Integer=15)
    ids = collect(sim_ids)
    isempty(ids) && error("no simulation ids given")

    # Build panels: a frame sequence per sim for a movie index, else one state SVG per sim.
    if _isMovieIndex(index)
        panels = [Panel(_snapshotPaths(id, index); title=title(id)) for id in ids]
    else
        fname = _stateFile(index)
        panels = Panel[]
        for id in ids
            svg = joinpath(_outputFolder(id), fname)
            if isfile(svg)
                push!(panels, Panel(svg; title=title(id)))
            else
                @warn "no $fname for simulation $id; skipping"
            end
        end
        isempty(panels) && error("no $fname found for the given simulations")
    end
    # core `montage` picks still vs. movie from the panel content and handles output + guard
    return montage(panels; panel_width, title_height, pad, output, overwrite, framerate)
end

end # module
