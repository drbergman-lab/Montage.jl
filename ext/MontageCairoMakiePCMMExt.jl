# tableau for PhysiCell simulations by id — the CairoMakie + PhysiCellModelManager adapter.
#
# Loaded when CairoMakie, PhysiCellModelManager, and PhysiCellOutput are all present. This is
# a thin adapter: it turns a `Simulation` id into an output folder, wraps it in a
# PhysiCellOutput handle (`PhysiCellSnapshot` for a still, `PhysiCellSequence` for a movie),
# and delegates to the folder-path `tableau` in MontageCairoMakiePhysiCellOutputExt. All the
# data-driven plotting logic lives there — the only PCMM-specific bit is id → folder.
#
# PhysiCellSnapshot/PhysiCellSequence are qualified to PhysiCellOutput's, since PCMM also
# defines types of those names.

module MontageCairoMakiePCMMExt

using Montage
using CairoMakie
using PhysiCellModelManager
using PhysiCellOutput

_outputFolder(id::Integer) = joinpath(trialFolder(Simulation, id), "output")
_isMovieIndex(index) = index === :all || index isa AbstractVector

"""
    tableau(::Type{Simulation}, sim_id; index=:final, substrates=<all>, colormap=:viridis,
            markersize=6, legend=:auto, size=(1000, 1000), framerate=15,
            output=<dataDir()/outputs/tableau.png|.mp4>, overwrite=false)

Compose one PhysiCell simulation state (CairoMakie + PhysiCellModelManager extension): the
**cell layer re-plotted as a scatter** colored by cell type, centered, with one **substrate
heatmap + colorbar** per substrate auto-arranged around it, all sharing a spatial extent.

The `index` value decides still image vs. movie, the same way as `montage`:
- `:final`/`:initial`/an `Integer` (a single snapshot selector) → a **still**;
- `:all` or a vector/range of snapshot indices → a **movie**: the whole scene animated over
  those snapshots via `Makie.record`, with a stable colorscale (each substrate's colorrange is
  fixed to its global min/max across frames) and a stable cell-type legend.

Other kwargs: `substrates` (which get satellites, default all), `colormap`, `markersize`,
`size`, and `framerate` (movies). `output` writes by default — `tableau.png` for a still
(`.svg`/`.pdf` also work) or `tableau.mp4` for a movie — erroring if it exists unless
`overwrite=true`; for a still, `output=nothing` returns the Makie `Figure` (a movie needs a
path). A `Simulation` object or a `PCMMOutput{Simulation}` is also accepted for `sim_id`.

This is a thin adapter over the folder-path `tableau` — it resolves the simulation's output
folder and delegates.

# Examples
```julia
using CairoMakie, PhysiCellModelManager, Montage
tableau(Simulation, 1)                                        # still: cells + every substrate
tableau(Simulation, 1; index=60, substrates=["oxygen"], legend=:rt, output="ox.png")
tableau(Simulation, 1; index=:all, output="tableau.mp4", framerate=15)   # movie over all snapshots
tableau(Simulation, 1; index=0:5:120)                         # movie over a subset
```
"""
function Montage.tableau(::Type{Simulation}, sim_id::Integer; index = :final,
                         output::Union{Nothing,AbstractString} =
                             joinpath(dataDir(), "outputs", _isMovieIndex(index) ? "tableau.mp4" : "tableau.png"),
                         kwargs...)
    folder = _outputFolder(sim_id)
    if _isMovieIndex(index)
        return tableau(PhysiCellOutput.PhysiCellSequence(folder); index, output, kwargs...)
    end
    snap = PhysiCellOutput.PhysiCellSnapshot(folder, index;
                                             include_cells = true, include_substrates = true, include_mesh = true)
    snap === missing && error("simulation $sim_id has no snapshot at index $(repr(index))")
    return tableau(snap; output, kwargs...)
end

# Accept a simulation object or a single-simulation run output.
Montage.tableau(sim::Simulation; kwargs...) = tableau(Simulation, sim.id; kwargs...)
Montage.tableau(out::PCMMOutput{Simulation}; kwargs...) = tableau(Simulation, out.trial.id; kwargs...)

end # module
