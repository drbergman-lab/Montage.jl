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
explicitly — e.g. `montage(Simulation, simulationIDs())` to include every simulation. A
single `Integer` id also works (a one-panel montage) — handy as `montage(Simulation, id;
index=:all)` for a single-simulation movie.

For convenience you can also pass PCMM objects directly, and their constituent simulations
are used: a trial (`Simulation`/`Monad`/`Sampling`/`Trial`), a run output (`PCMMOutput`), or
a vector of either — e.g. `montage(out)` or `montage([monad1, monad2]; index=:all)`.

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

# A single simulation id → a one-panel montage (mainly useful as `index=:all` for a
# single-simulation movie, since `storyboard` is static).
Montage.montage(::Type{Simulation}, sim_id::Integer; kwargs...) =
    montage(Simulation, [sim_id]; kwargs...)

# Accept trial objects and run outputs directly — resolve them to their constituent
# simulation ids and forward. A `Simulation`/`Monad`/`Sampling`/`Trial` (all `AbstractTrial`),
# a `PCMMOutput`, or a vector of either.
Montage.montage(trial::AbstractTrial; kwargs...) =
    montage(Simulation, simulationIDs(trial); kwargs...)
Montage.montage(trials::AbstractVector{<:AbstractTrial}; kwargs...) =
    montage(Simulation, simulationIDs(trials); kwargs...)
Montage.montage(out::PCMMOutput; kwargs...) =
    montage(Simulation, simulationIDs(out); kwargs...)
Montage.montage(outs::AbstractVector{<:PCMMOutput}; kwargs...) =
    montage(Simulation, reduce(vcat, simulationIDs.(outs); init=Int[]); kwargs...)

# --- storyboard --------------------------------------------------------------------------

# n evenly-spaced snapshot indices (from those actually present), spanning the run — so
# n=4 gives initial, two middles, and final. Returns all if the run has ≤ n snapshots.
function _evenSnapshots(sim_id::Integer, n::Integer)
    n >= 1 || error("n_snapshots must be ≥ 1; got $n")
    dir = _outputFolder(sim_id)
    files = sort!(filter(f -> occursin(r"^snapshot\d+\.svg$", f), readdir(dir)))
    isempty(files) && error("simulation $sim_id has no snapshot SVGs in $dir")
    idxs = [parse(Int, match(r"\d+", f).match) for f in files]
    n >= length(idxs) && return idxs
    return idxs[round.(Int, range(1, length(idxs); length=n))]
end

# Snapshot time (from output metadata), or `missing` if the snapshot can't be read.
function _snapshotTime(sim_id::Integer, sel)
    snap = PhysiCellSnapshot(sim_id, sel)
    return snap === missing ? missing : snap.time
end

_selectorLabel(sel::Symbol) = string(sel)
_selectorLabel(sel::Integer) = "snapshot $sel"

"""
    storyboard(::Type{Simulation}, sim_id; index=nothing, n_snapshots=…, title=(t -> "t = \$t"),
               ncols=nothing, panel_width=300, title_height=34, pad=12,
               output=joinpath(dataDir(), "outputs", "storyboard.svg"), overwrite=false)

Stitch **one** simulation's time evolution into a static filmstrip (PCMM extension), each
frame titled with its timestamp. `sim_id` is an `Integer`; you can also pass the simulation
object (`storyboard(sim)`) or a single-simulation run output (`storyboard(out)` where
`out isa PCMMOutput{Simulation}`).

Choose the timepoints one of two ways:

- **`index`** — a vector of snapshot selectors, each an `Integer` snapshot index or
  `:initial`/`:final` (matching PCMM's `PhysiCellSnapshot`), e.g. `[:initial, 30, 60, :final]`.
- **`n_snapshots`** (default 4) — pick that many evenly-spaced snapshots spanning the run,
  including the endpoints (initial, middles, final).

Pass **one** of them: `n_snapshots` defaults to `length(index)` when `index` is given (so
you never write `n_snapshots=nothing`); passing both with different lengths errors.

Titles come from each frame's simulation time via `title` (default `t -> "t = \$t"`, `t`
the PhysiCell `current_time`). `output` defaults under `dataDir()/outputs`, errors if it
exists unless `overwrite=true`, and `output=nothing` returns the SVG string. `ncols`
defaults to a single row.

# Examples
```julia
using PhysiCellModelManager, Montage

storyboard(Simulation, 1)                                  # 4 evenly-spaced frames
storyboard(Simulation, 1; n_snapshots=6)                   # 6 frames
storyboard(Simulation, 1; index=[:initial, 30, 60, :final])
storyboard(Simulation, 1; title=t -> "\$(round(t/1440; digits=1)) d")   # custom timestamp
```
"""
function Montage.storyboard(::Type{Simulation}, sim_id::Integer;
                            index=nothing,
                            n_snapshots::Integer = isnothing(index) ? 4 : length(index),
                            title = t -> "t = $t",
                            ncols::Union{Nothing,Integer}=nothing,
                            panel_width::Real=300, title_height::Real=34, pad::Real=12,
                            output::Union{Nothing,AbstractString}=joinpath(dataDir(), "outputs", "storyboard.svg"),
                            overwrite::Bool=false)
    isnothing(index) || n_snapshots == length(index) ||
        error("pass either `index` (a vector of timepoints) or `n_snapshots`, not both with different lengths (got n_snapshots=$n_snapshots, length(index)=$(length(index)))")
    selectors = isnothing(index) ? _evenSnapshots(sim_id, n_snapshots) : collect(index)
    dir = _outputFolder(sim_id)
    panels = map(selectors) do sel
        svg = joinpath(dir, _stateFile(sel))
        isfile(svg) || error("simulation $sim_id: no $(basename(svg)) (index $(repr(sel)))")
        t = _snapshotTime(sim_id, sel)
        Panel(svg; title = t === missing ? _selectorLabel(sel) : string(title(t)))
    end
    return storyboard(panels; ncols=something(ncols, length(panels)),
                      panel_width, title_height, pad, output, overwrite)
end

# Accept a single simulation directly, as an object or a single-simulation run output.
Montage.storyboard(sim::Simulation; kwargs...) = storyboard(Simulation, sim.id; kwargs...)
Montage.storyboard(out::PCMMOutput{Simulation}; kwargs...) = storyboard(Simulation, out.trial.id; kwargs...)

end # module
