```@meta
CurrentModule = Montage
```

# [PhysiCell simulations](@id physicell-page)

All three verbs drive straight from PhysiCell output: a grid comparing runs, a filmstrip of one run over time, and a multi-channel scene of one state — the grid and the scene still or animated.

## Two front doors

!!! tierbrief
    Simulation ids go through PhysiCellModelManager (PCMM). Output folder paths go through
    PhysiCellOutput, for work that does not use PCMM. The verbs and the keywords are the same on
    both sides; the panel titles and the default output path are what differ.

!!! tierfull
    Both doors read through PhysiCellOutput, so there is one reader path rather than two: the PCMM
    methods resolve a simulation id to its `output` folder, wrap it in a `PhysiCellSequence`, and
    delegate to the folder methods. A PCMM user therefore types one `using` line —
    PhysiCellModelManager depends on PhysiCellOutput, so loading PCMM activates both PhysiCell
    extensions, and no third `using` is involved. Name PhysiCellOutput yourself only when you are
    driving Montage from output folders without PCMM.

```julia
using PhysiCellModelManager, Montage    # ids:     montage(Simulation, [1, 2, 3])
using PhysiCellOutput, Montage          # folders: montage(PhysiCellSequence("run01/output"))
```

!!! tierdev
    `ext/MontagePhysiCellOutputExt.jl` holds the PhysiCell logic — snapshot selection, cell
    filtering, the legend, the colour plan. `ext/MontagePhysiCellModelManagerExt.jl` knows exactly
    one PCMM-specific thing, `joinpath(trialFolder(Simulation, id), "output")`, and forwards
    everything else. The CairoMakie pair for [`tableau`](@ref) splits the same way. See
    [Extensions](@ref extensions-page).

## What is read

!!! tierbrief
    [`montage`](@ref) and [`storyboard`](@ref) stitch PhysiCell's own snapshot renders —
    `output/initial.svg`, `output/final.svg`, `output/snapshot00000000.svg` and the rest — so a
    panel carries PhysiCell's styling exactly and neither verb needs a plotting stack.

!!! tierfull
    [`tableau`](@ref) is the exception. It sets the cells against each substrate field, which calls
    for real heatmaps and real colorbars, so it re-plots from the snapshot's cells, substrates and
    mesh instead of nesting a finished SVG. That is the one place a PhysiCell figure needs
    CairoMakie.

| Verb | Reads | Load |
|---|---|---|
| [`montage`](@ref) | `output/*.svg` | PhysiCellOutput, plus `Rsvg`, `Cairo`, `FFMPEG` for a movie |
| [`storyboard`](@ref) | `output/*.svg` | PhysiCellOutput |
| [`tableau`](@ref) | the snapshot's cells, substrates and mesh | CairoMakie and PhysiCellOutput |

## Comparing simulations — montage

!!! tierbrief
    Name the simulations you want: `montage(Simulation, simulationIDs())` is how you say "all of
    them". Each panel is one simulation, titled `Sim <id>` unless you pass your own `title` function
    of the id.

!!! tierfull
    `index` decides what the panels show and, with it, whether the result is a still or a movie. A
    still skips any simulation missing that snapshot, with a warning, and errors when none of them
    have it. A movie plays every panel's snapshot series in lockstep, aligned by index and truncated
    to the shortest, and is rendered through [`record`](@ref) — see [Movies](@ref movies-page).

| `index` | Result |
|---|---|
| `:final` (the default), `:initial`, or an `Integer` snapshot index | a still SVG |
| `:all`, or a `Vector`/range of snapshot indices | a movie |

```julia
using PhysiCellModelManager, Montage

montage(Simulation, simulationIDs())                        # final state of every simulation
montage(Simulation, [1, 2, 3]; index=:initial)              # initial states of three runs
montage(Simulation, [1, 2, 3]; index=10, output=nothing)    # 10th snapshot, as an SVG string
montage(Simulation, 7)                                      # a single-panel montage
montage(Simulation, simulationIDs(); title=id -> "run $id", ncols=4)
```

!!! tierfull
    The objects PCMM already hands you are accepted in place of ids, and resolve to their
    constituent simulations: a trial (`Simulation`, `Monad`, `Sampling`, `Trial`), a run output
    (`PCMMOutput`), or a vector of either.

```julia
montage(sampling)                             # every simulation in a trial
montage([monad1, monad2]; index=:all)         # two monads, animated
montage(out)                                  # out = run(sampling)

using Rsvg, Cairo, FFMPEG                     # the movie renderer
montage(Simulation, [1, 2, 22, 32]; index=:all, output="compare.mp4", framerate=15)
```

!!! tierfull
    The folder door takes a `PhysiCellSequence` per panel, or a vector of them, and titles each
    panel with the run folder's name — the directory holding `output`. A vector of
    `PhysiCellSnapshot`s works too, when the states you want to compare are not the same snapshot
    in every run. Everything else — `index`, `legend`, `cell_types`, `color`, and the core grid
    keywords such as `ncols` and `panel_width` — is identical to the id door.

```julia
using PhysiCellOutput, Montage

seqs = [PhysiCellSequence(joinpath(run, "output")) for run in ["run01", "run02", "run03"]]
montage(seqs)                                               # final states, titled run01, run02, …
montage(seqs; index=:all, output="compare.mp4")             # the same grid, animated

snaps = [PhysiCellSnapshot("run01/output", :final), PhysiCellSnapshot("run02/output", 60)]
montage(snaps)                                              # states chosen run by run
```

## One simulation over time — storyboard

!!! tierbrief
    [`storyboard`](@ref) takes one simulation and lays its timepoints out in order, each frame
    titled with its simulation time. It is always static: the filmstrip is the point.

!!! tierfull
    Choose the timepoints one of two ways, not both. `index` is a vector of selectors, each an
    `Integer` snapshot index or `:initial`/`:final`, and gives you exact control. `n_snapshots`
    (default 4) takes that many evenly spaced snapshots spanning the run, endpoints included.
    Passing both with different lengths errors. `title` is a function of the frame's simulation
    time, so the units are yours to choose; `ncols` wraps a long strip into a block.

```julia
storyboard(Simulation, 1)                                   # 4 evenly spaced frames
storyboard(Simulation, 1; n_snapshots=6)
storyboard(Simulation, 1; index=[:initial, 30, 60, :final])
storyboard(Simulation, 1; title = t -> "$(round(t / 1440; digits=1)) d")
storyboard(Simulation, 1; n_snapshots=8, ncols=4, output="strip.svg", overwrite=true)
```

!!! tierfull
    Through the folder door, pass the sequence itself. The keywords are the same.

```julia
storyboard(PhysiCellSequence("run01/output"); n_snapshots=5)
```

## A multi-channel scene — tableau

!!! tierbrief
    [`tableau`](@ref) puts one simulation state in the middle — the cells, re-plotted as a scatter
    — and rings it with one heatmap and colorbar per substrate. Every panel shares the mesh's
    spatial extent, so a feature in the cells sits over the same coordinates in every field. It
    needs CairoMakie as well.

!!! tierfull
    `index` works exactly as it does for [`montage`](@ref): a single selector gives a still, `:all`
    or a vector of indices animates the whole scene through `Makie.record`, with each substrate's
    colorrange fixed to its global min/max so the fields stay comparable frame to frame.
    `substrates` chooses which fields get satellites (all of them by default), `colormap` is the
    substrate ramp, `markersize` the cell size, and `size` the figure size.

```julia
using CairoMakie, PhysiCellModelManager, Montage

tableau(Simulation, 1)                                          # cells plus every substrate
tableau(Simulation, 1; index=60, substrates=["oxygen"], output="oxygen.pdf")
tableau(Simulation, 1; index=:all, framerate=15)                # writes tableau.mp4
tableau(Simulation, 1; index=:final, size=(1400, 1400), output=nothing)   # returns the Figure
```

!!! tierfull
    A still accepts `output=nothing` and returns the `Figure` for further Makie work; a movie has
    to be written to a file. `.png` is the default, `.svg` and `.pdf` also work — see
    [Tableau](@ref tableau-page) for which to choose.

```julia
using CairoMakie, PhysiCellOutput, Montage

tableau(PhysiCellSnapshot("run01/output", :final))
tableau(PhysiCellSequence("run01/output"); index=0:5:120, output="scene.mp4")
```

## Choosing which cells appear

!!! tierbrief
    `cell_types` (one name or a vector of names) and `include_dead=false` restrict which cells are
    drawn. Both work on all three verbs, with the same meaning.

!!! tierfull
    For the stitched verbs this is a pure edit of the snapshot SVG: PhysiCell tags every cell as
    `<g id="cell442" type="tumor_epi" dead="true">`, so the non-matching groups are dropped and
    nothing is re-rendered. PhysiCell's own "N agents" caption is rewritten to the number actually
    shown, since a figure captioned `511 agents` while displaying 200 of them would be wrong, and
    an automatic legend narrows to the types you kept. [`tableau`](@ref) applies the same selection
    to the data before plotting, and validates the names against the config's full type list, so
    filtering to a type that happens to be absent from one snapshot gives an empty panel rather
    than an error.

```julia
montage(Simulation, simulationIDs(); cell_types="tumor_epi")
storyboard(Simulation, 1; cell_types=["tumor_epi", "caf"], include_dead=false)
tableau(Simulation, 1; cell_types="caf", include_dead=false)
```

## The cell-type legend

!!! tierbrief
    The stitched verbs include a cell-type key by default (`legend=:auto`), in PhysiCell's own
    colours. `legend=nothing` suppresses it; `legend_position` places it.

!!! tierfull
    The entries come from each run's `output/legend.svg`, which lists every cell type the *config*
    defines together with the colour PhysiCell drew it in, and they are unioned across panels so a
    sweep that mixed configs still explains every type any panel can contain. Because the key
    describes what the model can contain rather than what one snapshot happens to show, one legend
    is correct for every frame of a movie, and it is drawn into each of them. The entries are drawn
    as flat circles and text, so they stay editable in Illustrator and PowerPoint. `legend_position`
    is independent of the content: `:auto` uses the free cells trailing the last row when the grid
    has any, costing no space, and otherwise a band below.

```julia
montage(Simulation, [1, 2]; legend=nothing)                    # no key
montage(Simulation, [1, 2]; legend_position=:bottom)           # a band below, not the spare cells
montage(Simulation, [1, 2]; legend=[("treated", "red"), ("control", "grey")])
montage(Simulation, [1, 2]; legend="key.svg")                  # nest a hand-made file
```

!!! tierdev
    The parse lives in `Montage._cellTypeLegend(folders)`, a hook declared in the core so that
    [`tableau`](@ref) can reach it too: the tableau draws its cells in the same PhysiCell colours,
    which is what keeps a tableau and a montage of one run agreeing. A run with no `legend.svg` —
    older PhysiCell, some 3-D runs — yields no entries, and `:auto` then means no legend.

!!! tierjournal "2026-08-05 — the legend comes from PhysiCell's own legend.svg"
    The run already writes one file listing every cell type the config defines, with the colours
    PhysiCell drew them in. Reading it costs one ~1.5 KB file per simulation and is independent of
    frame count, and because it describes what the model can contain rather than what one snapshot
    happens to show, a single legend is correct for every frame of a movie. Rejected scanning
    snapshots for the types actually present: it is per-frame work, and it produces a legend that
    changes as cells appear and die. The entries are drawn as flat circles and text rather than
    nested as an SVG so they stay editable in Illustrator and PowerPoint.

## Colouring cells by data

!!! tierbrief
    `color` names any column of the cells table — `cellLabels(snapshot)` lists them — and repaints
    each cell along `colormap`. For the stitched verbs the cell-type key becomes a colorbar, since
    per-type swatches would describe colours the figure does not use.

!!! tierfull
    Each cell group in the snapshot SVG carries its `id="cell442"`, which joins to the `ID` column
    of the cells table, so a column can drive the fill without re-rendering anything. The value
    range is pooled over every panel and every frame and computed *after* filtering: a colour then
    means the same quantity everywhere in the figure, which is the whole point of a montage, and
    cells you excluded cannot stretch the scale. The stitched path carries a small built-in
    colormap set — `:viridis`, `:plasma`, `:grays` — and takes a numeric column only; a categorical
    column belongs in [`tableau`](@ref), which draws one labelled series per value.

```julia
using PhysiCellOutput
cellLabels(PhysiCellSnapshot("run01/output", :final))   # the columns available to `color`

montage(Simulation, [1, 2, 3]; color=:pressure, colormap=:plasma)
storyboard(Simulation, 1; n_snapshots=5, color=:total_volume)
```

!!! tierfull
    [`tableau`](@ref) re-plots, so it has Makie's full colormap set and both visual modes. `color`
    picks the column — the cells' own columns, plus `:cell_type_name` — `cell_colormap` is the cell
    ramp (`colormap` stays the substrates'), and `color_mode` overrides the automatic choice
    between the two modes.

| `color` column | `color_mode=:auto` draws | Key |
|---|---|---|
| `:cell_type_name` (the default), or any string or `Bool` column | one labelled scatter series per value | a legend |
| any other numeric column, such as `:pressure` | one scatter on `cell_colormap` | a colorbar |

```julia
tableau(Simulation, 1; color=:pressure, cell_colormap=:plasma)
tableau(Simulation, 1; color=:current_phase, color_mode=:categorical)
tableau(Simulation, 1; index=:all, color=:pressure, output="pressure.mp4")
```

!!! tierfull
    A numeric column whose values are really labels — `:current_phase` is the usual one — reads as
    continuous unless you say `color_mode=:categorical`. In a movie a continuous `color` gets a
    globally fixed colorrange, its min/max over every frame after filtering. That matters more than
    it sounds: at `t = 0` a quantity like pressure is often uniformly zero, and a per-frame scale
    would spread that single value across the whole ramp and show a meaningless riot of colour.

!!! tierjournal "2026-08-05 — a built-in colormap set on the stitched path"
    Colouring cells by a data value rewrites fills in the snapshot SVG, so it needs a colormap but
    not a plotting stack. Carrying `:viridis`, `:plasma` and `:grays` in the core keeps `montage`
    and `storyboard` dependency-free; `tableau` already re-plots through Makie and has the full set.

## Where the files go

!!! tierbrief
    Every verb writes by default: the id door under `dataDir()/outputs`, where the rest of a PCMM
    project's output lives, and the folder door into the current directory. A stitched verb hands
    the composed SVG back as well; a written tableau or movie hands back the path.

!!! tierfull
    Writing errors if the file already exists, unless you pass `overwrite=true` — a guard worth
    having when a figure is regenerated from a script. `output=nothing` skips writing and hands
    back the in-memory result: the composed SVG string for a still montage or storyboard, a
    [`MontageSpec`](@ref) for an animated montage, a `Figure` for a still tableau. A movie must be
    written to a path.

| Call | Default `output` |
|---|---|
| `montage(Simulation, …)` | `dataDir()/outputs/montage.svg`, or `montage.mp4` for a movie |
| `storyboard(Simulation, …)` | `dataDir()/outputs/storyboard.svg` |
| `tableau(Simulation, …)` | `dataDir()/outputs/tableau.png`, or `tableau.mp4` for a movie |
| `montage(seqs)`, `storyboard(seq)` | `montage.svg` / `storyboard.svg`, in the current directory |
| `tableau(snap)`, `tableau(seq)` | `tableau.png`, or `tableau.mp4` for a movie |
