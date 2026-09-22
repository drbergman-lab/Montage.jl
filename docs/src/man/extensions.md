```@meta
CurrentModule = Montage
```

# [Extensions](@id extensions-page)

Montage's core has no dependencies at all — its `Project.toml` carries no `[deps]` section — and everything that needs a heavy stack arrives as a package extension, which Julia loads for you the moment its trigger packages are in the session.

## The six extensions

!!! tierbrief
    They fall into three groups: one extension renders montage movies, two are doors onto
    PhysiCell output (by folder, or by simulation id), and three build on CairoMakie to
    provide [`tableau`](@ref). Each one only adds methods to names the core already owns —
    `montage`, `storyboard`, `tableau`, and the renderer hook behind `record`.

!!! tierfull
    The two PhysiCell doors are deliberately lopsided. `MontagePhysiCellOutputExt` holds the
    reading logic; `MontagePhysiCellModelManagerExt` is a thin adapter that resolves a
    simulation id to its output folder and hands off. The CairoMakie trio splits the same way:
    the layout engine, then the PhysiCell plotting, then the id adapter.

    What none of them adds is a Makie *backend* for `montage` or `storyboard`. Those two verbs
    stitch SVG, which is lossless, editable and free of heavy dependencies, so they stay in the
    core whatever you load; `backend=:makie` errors. [Tableau](@ref tableau-page) is the one verb that
    re-plots from data, which is why it is the one verb CairoMakie is required for.

| Extension | Trigger packages | What it adds |
| --- | --- | --- |
| `MontageMovieExt` | `Rsvg`, `Cairo`, `FFMPEG` | the renderer behind [`record`](@ref): each stitched SVG frame rasterized, then encoded with FFMPEG |
| `MontagePhysiCellOutputExt` | `PhysiCellOutput` | [`montage`](@ref) and [`storyboard`](@ref) over PhysiCell output folders — `PhysiCellSequence` and `PhysiCellSnapshot` |
| `MontagePhysiCellModelManagerExt` | `PhysiCellModelManager`, `PhysiCellOutput` | those same two verbs by simulation id: `montage(Simulation, ids)` |
| `MontageCairoMakieExt` | `CairoMakie` | `tableau` in its data-agnostic form, `tableau(focal, satellites)` |
| `MontageCairoMakiePhysiCellOutputExt` | `CairoMakie`, `PhysiCellOutput` | `tableau` of a PhysiCell output folder, still or movie |
| `MontageCairoMakiePCMMExt` | `CairoMakie`, `PhysiCellModelManager`, `PhysiCellOutput` | `tableau` by simulation id |

## One `using` line is usually enough

!!! tierbrief
    An extension activates once all of its trigger packages are present, so you name only the
    package you actually work with. `using PhysiCellModelManager` covers both PhysiCell
    extensions; `using PhysiCellOutput` is the door for people driving Montage straight from
    output folders.

!!! tierfull
    A Julia extension triggers when its trigger packages are loaded *for any reason*, including
    as another package's dependency rather than by name in your script. PhysiCellModelManager
    depends on PhysiCellOutput, so `using PhysiCellModelManager` puts both in the session and
    satisfies the `["PhysiCellModelManager", "PhysiCellOutput"]` trigger without you typing the
    second name. The trigger list names both because the extension's code uses both: it calls
    PCMM to resolve an id to a folder, then constructs a `PhysiCellOutput.PhysiCellSequence`
    over it. Montage's compat bound is `PhysiCellModelManager = "0.4, 0.5"`, so this holds for
    every version Montage supports.

    CairoMakie is orthogonal to all of that. On its own it adds the generic `tableau`; combined
    with either PhysiCell door it also adds the simulation methods, because the fifth and sixth
    rows of the table above are separate extensions with their own triggers.

```julia
using Montage, PhysiCellModelManager              # montage/storyboard by simulation id
using Montage, PhysiCellOutput                    # ...from output folders, without PCMM
using Montage, CairoMakie                         # tableau(focal, satellites)
using Montage, CairoMakie, PhysiCellModelManager  # tableau(Simulation, id)
using Montage, Rsvg, Cairo, FFMPEG                # montage movies
```

!!! tierjournal "2026-09-21 — PCMM 0.4+ brings PhysiCellOutput along"
    The PhysiCellModelManager extension is triggered by PCMM and PhysiCellOutput together,
    because it uses both. PhysiCellModelManager 0.4 took PhysiCellOutput as a dependency, so loading
    PCMM now loads PhysiCellOutput too and the trigger is satisfied without the user naming it —
    verified on 0.4.0 and 0.5.1. The compat bound rose to "0.4, 0.5" to make that promise true rather
    than conditional: under 0.3 the extension needed a `using PhysiCellOutput` the reader had no way
    to guess.

## When something is missing

!!! tierbrief
    A verb whose extension is absent errors with the packages to load written into the message,
    so the fix is the error text.

!!! tierfull
    The PhysiCell methods are the exception, because there is nothing for Montage to catch. Without
    PhysiCellModelManager the name `Simulation` does not exist, so the call fails before Montage
    sees it; without PhysiCellOutput you cannot build a `PhysiCellSequence` to pass either. A folder
    path handed to `montage` instead falls through to the SVG backend, which wants one SVG file per
    panel — see [PhysiCell simulations](@ref physicell-page) for what to pass.

```julia
tableau(Simulation, 1)                        # PCMM loaded, CairoMakie not
# ERROR: `tableau` needs the CairoMakie extension (and PhysiCellOutput or PhysiCellModelManager
#        for simulations) — run `using CairoMakie, PhysiCellOutput` or
#        `using CairoMakie, PhysiCellModelManager` first to get it.

montage([Panel(["a/f1.svg", "a/f2.svg"])])    # no Rsvg/Cairo/FFMPEG loaded
# ERROR: montage movies need the movie extension — run `using Rsvg, Cairo, FFMPEG` to load it

montage(Simulation, [1, 2, 3])                # UndefVarError: `Simulation` is PCMM's name

montage(["run1/output"])                      # a folder is not an SVG file
# ERROR: SVG file not found: run1/output
```

## Why extensions rather than separate packages

!!! tierbrief
    Extensions decouple what you type from where the code lives. `using Montage` is the only
    Montage import there ever is, and loading CairoMakie or a PhysiCell package widens what the
    same three verbs accept.

!!! tierfull
    The alternative worth weighing is a companion package — a PhysiCell-flavoured Montage you
    would install and import alongside this one. It costs a second name to learn, and its verbs
    could not be `montage` and `storyboard` unless it depended on Montage and added methods to
    them, which is exactly what an extension does with none of the packaging. So: the core carries
    no heavy dependency, `montage` stays one function whose meaning never shifts, and
    `methods(montage)` simply grows as you load more.

    The constraint that makes this work is that an extension may only add methods to functions the
    core already owns. That is why the verbs, the [`Panel`](@ref) and [`MontageSpec`](@ref) types,
    and the backend selectors are all declared in the core: an extension cannot introduce a new
    entry point that a user who typed only `using Montage` would be able to reach.

!!! tierjournal "2026-07-27 — two front doors, one reader path"
    PhysiCell support ships as Montage extensions rather than a separate PhysiCellMontage.jl
    package. The clunky name was not worth it, and extensions already decouple what a user types from
    where code lives — everyone still types `using Montage`. Folder paths go through
    MontagePhysiCellOutputExt, which holds the real logic; simulation ids go through
    MontagePhysiCellModelManagerExt, a thin adapter that resolves an id to a folder and delegates.
    Both read through PhysiCellOutput, so there is one reader path rather than two implementations
    that could drift.

## How an extension is wired

```toml
[weakdeps]
CairoMakie = "13f3f980-e62b-5c42-98c6-ff1f3baf88f0"
PhysiCellOutput = "61ac5edc-a73d-4441-b68d-d9b510422d04"

[extensions]
MontageCairoMakieExt = "CairoMakie"
MontageCairoMakiePhysiCellOutputExt = ["CairoMakie", "PhysiCellOutput"]
```

!!! tierdev
    Trigger packages go in `[weakdeps]`, never `[deps]` — a `[deps]` entry would make the
    dependency compulsory and defeat the whole arrangement. Each `[extensions]` key is the module
    name and must match a file under `ext/` (`MontageCairoMakieExt` ↔ `ext/MontageCairoMakieExt.jl`),
    and its value lists every trigger package the module's code touches, not just the headline one.
    Give each weakdep a `[compat]` bound as well; that is the only place a version constraint on it
    can live.

    Inside `ext/`, a method that fills a core hook is written qualified — `function
    Montage.tableau(…)`, `function Montage._recordSVGMovie(…)`. A hook the core cannot implement at
    all is declared there as an empty generic function (`function _cellTypeLegend end`, in
    `src/svg_backend.jl`) purely so the extension has something to extend. A hook the core *can* fall
    back on is written on abstract or untyped arguments — `_montage(::MontageBackend, …)`,
    `_recordSVGMovie(spec, path, framerate, scale)` — so the extension's concrete method is strictly
    more specific and no method-overwrite warning fires either way.

    `docs/make.jl` loads all six weakdeps and errors if `Base.get_extension` returns `nothing` for
    any of them, so a mis-wired trigger list fails the docs build instead of quietly emptying the
    [API reference](@ref reference-page).
