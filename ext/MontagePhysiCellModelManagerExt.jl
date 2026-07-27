# PCMM convenience methods for Montage — the PhysiCellModelManager adapter.
#
# Loaded when PhysiCellModelManager and PhysiCellOutput are both present. This is a thin
# adapter: it resolves each `Simulation` id to its output folder, wraps it in a
# PhysiCellOutput `PhysiCellSequence`, and delegates to the folder-path `montage`/`storyboard`
# in MontagePhysiCellOutputExt. The only PCMM-specific knowledge here is id → output folder;
# all the PhysiCell reading/globbing lives in the folder-path extension.
#
# `Simulation`, `simulationIDs`, `trialFolder`, and `dataDir` are ModelManager's, re-exported
# by PCMM. `PhysiCellSequence` is qualified to PhysiCellOutput's, since PCMM also defines a
# type of that name.

module MontagePhysiCellModelManagerExt

using Montage
using PhysiCellModelManager
using PhysiCellOutput

_outputFolder(id::Integer) = joinpath(trialFolder(Simulation, id), "output")
_isMovieIndex(index) = index === :all || index isa AbstractVector
_sequence(id::Integer) = PhysiCellOutput.PhysiCellSequence(_outputFolder(id))

# --- montage -----------------------------------------------------------------------------

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

The `index` value decides still image vs. movie:

- **Still image** — `index` is `:final`, `:initial`, or an `Integer` snapshot: one panel per
  simulation. Simulations missing the file are skipped with a warning. Writes an SVG.
- **Movie** — `index` is `:all` or a vector/range of snapshot indices (e.g. `0:5:120`): each
  panel plays that simulation's snapshot sequence in lockstep. Writes a video via
  [`record`](@ref) (needs `using Rsvg, Cairo, FFMPEG`).

`output` defaults to `dataDir()/outputs/montage.svg` (still) or `…/montage.mp4` (movie); it
errors if the file exists unless `overwrite=true`. `output=nothing` returns the in-memory
result (SVG string, or a [`MontageSpec`](@ref) for a movie). `framerate` applies to movies.

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
                         index = :final, title = (id -> "Sim $id"),
                         output::Union{Nothing,AbstractString} =
                             joinpath(dataDir(), "outputs", _isMovieIndex(index) ? "montage.mp4" : "montage.svg"),
                         kwargs...)
    ids = collect(sim_ids)
    isempty(ids) && error("no simulation ids given")
    seqs = _sequence.(ids)
    idmap = Dict(seq.folder => id for (seq, id) in zip(seqs, ids))   # seq → id, for the title
    return montage(seqs; index, title = (seq -> title(idmap[seq.folder])), output, kwargs...)
end

# A single simulation id → a one-panel montage (mainly useful as `index=:all` for a
# single-simulation movie, since `storyboard` is static).
Montage.montage(::Type{Simulation}, sim_id::Integer; kwargs...) =
    montage(Simulation, [sim_id]; kwargs...)

# Accept trial objects and run outputs directly — resolve them to their constituent
# simulation ids and forward.
Montage.montage(trial::AbstractTrial; kwargs...) =
    montage(Simulation, simulationIDs(trial); kwargs...)
Montage.montage(trials::AbstractVector{<:AbstractTrial}; kwargs...) =
    montage(Simulation, simulationIDs(trials); kwargs...)
Montage.montage(out::PCMMOutput; kwargs...) =
    montage(Simulation, simulationIDs(out); kwargs...)
Montage.montage(outs::AbstractVector{<:PCMMOutput}; kwargs...) =
    montage(Simulation, reduce(vcat, simulationIDs.(outs); init = Int[]); kwargs...)

# --- storyboard --------------------------------------------------------------------------

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
  `:initial`/`:final`, e.g. `[:initial, 30, 60, :final]`.
- **`n_snapshots`** (default 4) — that many evenly-spaced snapshots spanning the run,
  including the endpoints.

Pass **one** of them: `n_snapshots` defaults to `length(index)` when `index` is given;
passing both with different lengths errors.

Titles come from each frame's simulation time via `title` (default `t -> "t = \$t"`).
`output` defaults under `dataDir()/outputs`, errors if it exists unless `overwrite=true`, and
`output=nothing` returns the SVG string. `ncols` defaults to a single row.

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
                            output::Union{Nothing,AbstractString} =
                                joinpath(dataDir(), "outputs", "storyboard.svg"),
                            kwargs...)
    return storyboard(_sequence(sim_id); output, kwargs...)
end

# Accept a single simulation directly, as an object or a single-simulation run output.
Montage.storyboard(sim::Simulation; kwargs...) = storyboard(Simulation, sim.id; kwargs...)
Montage.storyboard(out::PCMMOutput{Simulation}; kwargs...) = storyboard(Simulation, out.trial.id; kwargs...)

end # module
