```@meta
CurrentModule = Montage
```

# [Architecture](@id architecture-page)

Where to make a change: what lives in which file, how one call travels through them, what must not break, and how to run the tests and the docs.

## Module map

!!! tierbrief
    The core holds every verb, every type and the SVG stitching backend, and takes no heavy
    dependency. The six extensions add methods to names the core already owns.

| `src/` | Holds |
|---|---|
| `src/Montage.jl` | The module. Includes the files below in order and exports `Panel`, `MontageSpec`, `montage`, `storyboard`, `tableau`, `record`. |
| `src/types.jl` | `Panel`, `MontageSpec`, the backend selectors (`MontageBackend`, `SVGBackend`, `MakieBackend`, `montageBackend`), `_asPanels`, `_isAnimated`, `_frameTransform`, `_TITLE_FONT_SIZE`. |
| `src/svg_backend.jl` | The string-stitch backend: `_svgDimensions`, `_nestedSVG`, `_svgSource`, `_svgGrid`, the legend machinery (`_normalizeLegend`, `_legendLayout`, `_svgLegend`), and the core-declared `_cellTypeLegend` hook. |
| `src/montage_verb.jl` | The `montage` verb, `_resolvedNcols`, `_writeSVG`, `_assertWritable`. Named `montage_verb.jl` because macOS's case-insensitive filesystem would collide a `montage.jl` with `Montage.jl`. |
| `src/movie.jl` | `_montageSpec`, `_svgFrame`, the `record` entry point, and the `_recordSVGMovie` fallback that errors without the movie extension. |
| `src/storyboard.jl` | The `storyboard` verb, which rejects animated panels. |
| `src/tableau.jl` | Declares `tableau`; the core method only errors with a "load CairoMakie" hint. |

| `ext/` | Triggers | Adds |
|---|---|---|
| `ext/MontageMovieExt.jl` | Rsvg, Cairo, FFMPEG | `_rasterizeSVG` and the concrete `Montage._recordSVGMovie`: rasterize each stitched frame, encode with FFMPEG. |
| `ext/MontagePhysiCellOutputExt.jl` | PhysiCellOutput | `montage` on `PhysiCellSequence` and `PhysiCellSnapshot`, `storyboard` on `PhysiCellSequence`: snapshot globbing, `_cellTransform` filtering and recolouring, `legend.svg` parsing, `_colorPlan`, `_svgColorbar`. |
| `ext/MontagePhysiCellModelManagerExt.jl` | PhysiCellModelManager, PhysiCellOutput | `montage`/`storyboard` by simulation id, trial or `PCMMOutput`. Knows `_outputFolder` and nothing else; delegates. |
| `ext/MontageCairoMakieExt.jl` | CairoMakie | The layout engine: `_ringSlots`, `_tableauFigure`, `_placeLegend!`, and the data-agnostic `tableau(focal, satellites)`. |
| `ext/MontageCairoMakiePhysiCellOutputExt.jl` | CairoMakie, PhysiCellOutput | Data-driven `tableau` of a snapshot or folder: `_substrateGrid`, `_cellMask`, `_physiCellPalette`, `_tableauStill`, `_tableauMovie`. |
| `ext/MontageCairoMakiePCMMExt.jl` | CairoMakie, PhysiCellModelManager, PhysiCellOutput | `tableau` by simulation id, `Simulation` object or `PCMMOutput{Simulation}`. Resolves the folder and delegates. |

!!! tierdev
    Two file pairs look redundant and are not. `MontagePhysiCellOutputExt` holds the PhysiCell
    logic and `MontagePhysiCellModelManagerExt` is a thin adapter over it; the same split repeats
    for `tableau` across `MontageCairoMakiePhysiCellOutputExt` and `MontageCairoMakiePCMMExt`.
    Put new PhysiCell behaviour in the folder extension and both doors get it.

    `montageBackend(:makie)` returns a `MakieBackend()` that no method implements, so
    `montage`/`storyboard` with `backend=:makie` reach the abstract-type fallbacks
    `_montage`/`_storyboard(::MontageBackend, …)` and error. Those two verbs stitch SVG; `tableau`
    is the CairoMakie verb and dispatches on its arguments, not on a backend selector.

!!! tierjournal "2026-08-05 — a Plots.jl backend, measured and declined"
    The motivation was a downstream app compiling to 1.63 GB against a 500 MB target. Measured
    three builds: no plotting stack at all 700 MB, plus Plots.jl 1.27 GB, the current CairoMakie
    1.63 GB. The floor alone exceeds the target, so no plotting library could have met it;
    swapping buys 22% and Plots is itself a 570 MB dependency. Not worth maintaining a second
    backend.

## The data flow of one call

!!! tierbrief
    Follow one movie call from a simulation id to an encoded file. Every hop below is a method
    on a name the core owns.

```julia
using Montage, PhysiCellModelManager, Rsvg, Cairo, FFMPEG
montage(Simulation, ids; index=:all, output="compare.mp4")
```

| # | Function | File |
|---|---|---|
| 1 | `montage(::Type{Simulation}, sim_ids; …)`, through `_outputFolder` and `_sequence` | `ext/MontagePhysiCellModelManagerExt.jl` |
| 2 | `montage(::AbstractVector{<:PhysiCellSequence}; …)`, through `_frameIndices`, `_frameSVGs`, `_colorPlan`, `_legendFor` | `ext/MontagePhysiCellOutputExt.jl` |
| 3 | `montage(panels; …)`, through `_asPanels` and `_normalizeLegend` | `src/montage_verb.jl` |
| 4 | `_montageSpec`, building the `MontageSpec` | `src/movie.jl` |
| 5 | `record(spec, output; framerate, overwrite)`, through `_assertWritable` | `src/movie.jl` |
| 6 | `_recordSVGMovie`: `_rasterizeSVG` per frame, then `FFMPEG.exe` | `ext/MontageMovieExt.jl` |
| 7 | `_svgFrame(spec, t)` per frame, which calls `_svgGrid` | `src/movie.jl`, `src/svg_backend.jl` |

!!! tierdev
    Hop 1 turns each id into `trialFolder(Simulation, id)/output` and wraps it in a
    `PhysiCellOutput.PhysiCellSequence`, keeping a folder-to-id map so the caller's `title`
    function still sees ids. Hop 2 is where PhysiCell knowledge lives: it globs the snapshot SVG
    paths, asks `_colorPlan` for one transform per panel (a `Vector` of them, one per frame, when
    `color` is set), and resolves `legend=:auto` into `(label, colour)` entries from each run's
    `legend.svg` — or into a colorbar draw function when cells are recoloured by data. It then
    builds `Panel`s whose content is a `Vector` of frame paths and hands them to the core verb.

    Hop 3 sees animated panels and branches to the spec builder rather than the still backend.
    Hop 4 truncates to the shortest frame sequence (warning when the counts differ) and resolves a
    legend *file* to text once, so no frame re-reads it. Hop 6 raster-pads each frame to even
    dimensions, which is what `yuv420p` H.264 needs, and writes a GIF instead when the path ends
    in `.gif`. Hop 7 reuses the static grid logic unchanged, indexing each panel's transform by
    frame.

    The still path (`index=:final`) diverges at hop 2, which builds one-image panels — warning
    past any folder missing that snapshot — so hop 3 takes `_montage(::SVGBackend, …)` straight to
    `_svgGrid` and `_writeSVG`, and hops 4 to 7 never run: no spec, no rasterizer, no FFMPEG.

## Invariants

| Invariant | What breaks if it goes |
|---|---|
| Every verb, type and selector is defined in `src/`; extensions only add methods. | An extension cannot introduce a name its parent lacks, and extensions cannot `using` one another. A verb declared in an extension is unreachable from `using Montage`, and a helper two extensions share has nowhere to live — `_cellTypeLegend` is declared in core for exactly that reason. |
| A core fallback is deliberately *more general* than the method an extension adds (`_recordSVGMovie`, `_montage(::MontageBackend, …)`). | Matching signatures make the extension's method an overwrite, which Julia rejects during precompilation. `_cellTypeLegend` takes the other escape: declared with no methods at all. |
| CairoMakie, PhysiCellOutput, PhysiCellModelManager, Rsvg, Cairo and FFMPEG stay in `[weakdeps]`. | `using Montage` drags in a plotting stack and the SVG default stops being the light path. The test target's `[extras]` is `Test` alone for the same reason. |
| Intrinsic SVG sizes are parsed by `_svgDimensions`, never hardcoded. PhysiCell's `final.svg` happens to be 1000×1070. | Panels clip or stretch the moment a source renders at another size: a different domain, a 3-D run, an SVG from another tool. |
| `Panel`'s default `transform` is `identity`, and identity stays free. | `identity` returns the very same string object, so an untransformed composition is byte-identical to one built with no transform support. Anything that rewrites panel text unconditionally costs every panel and forfeits that. |
| Titles and drawn legends are emitted as real `<text>` and flat `<circle>` markers. | The composed figure stops being editable in Illustrator or PowerPoint, which is the reason to stitch vector SVG at all. CairoMakie's `.svg` converts text to glyph outlines, so it is not a substitute. |
| PhysiCellOutput is the single reader path, and the PCMM extension stays a thin adapter over it. | Two readers drift, and the same run renders differently depending on which door the user came through. |
| A `color` range is pooled across every panel and every frame, and computed after `cell_types`/`include_dead` filtering (`_colorPlan`). | A colour stops meaning the same thing across the figure, which is the one job a montage has; cells that are never drawn stretch the scale. |
| Every write goes through `_assertWritable`. | Nothing stands between a re-run and an overwritten figure. |

## Running the tests

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
julia --project=. test/runtests.jl
```

!!! tierdev
    The second form runs the same file outside Pkg's sandbox, which is faster to iterate on.
    `test/runtests.jl` reads no arguments, so there is no filter flag: to run a single block,
    paste it into a REPL that has `using Montage, Test`. Testsets are named
    `"<area> — <behaviour>"` (`"legend — drawn entries"`, `"Panel transform — per-frame in a
    movie"`) and nested under one top-level `@testset "Montage.jl"`. Each block builds its own
    fixtures from the SVG string constants at the top of the file, most through the
    `withtmpsvgs` helper, so no block depends on another having run.

    The suite depends on `Test` and nothing else: no PhysiCellModelManager, no PhysiCellOutput, no
    CairoMakie, no external data. It exercises the SVG backend on tiny hand-written SVGs of
    differing intrinsic sizes, which is what pins the max-aspect grid logic, the legend placement
    rules and the byte-identical guarantees. That means it cannot catch broken `[weakdeps]` or
    `[extensions]` wiring — the docs build does, because it loads all six.

## Building the docs

```sh
julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

!!! tierdev
    `docs/Project.toml` lists every weak dependency in `[deps]` on purpose. `docs/make.jl` loads
    them, then binds each extension module in `Main` through `Base.get_extension` and errors by
    name if one is missing, so a broken extension fails the build instead of quietly emptying the
    API reference. `makedocs` passes all six modules alongside `Montage`, with
    `checkdocs=:all` — every docstring in the core and in the extensions has to appear on some
    page, so [API reference](@ref reference-page) and the internal reference below together cover
    all of them.

    `docs/make.jl` includes `docs/journal.jl`, which regenerates `docs/src/dev/journal.md` from
    every `!!! tierjournal` block under `docs/src`, newest first, and warns when a page's tier
    blocks run out of order (they go brief, full, dev, journal within a section). The generated
    journal is committed, so it reads on GitHub too; edit the blocks on their own pages, never
    that file. Docstrings are rendered by `docs/src/reference.md` and by the `@autodocs` blocks
    below, so pages link to them with `` [`montage`](@ref) `` rather than declaring their own.

## Adding an extension

| Step | Where |
|---|---|
| Declare the function, type or hook in the core first. | `src/` — an extension can only add methods to a name the parent already owns. |
| Add the trigger package to `[weakdeps]` and an `[extensions]` entry naming every trigger. | `Project.toml`, plus a `[compat]` bound for the new weakdep. |
| Name the file for the extension module, and make the module name match. | `ext/Montage<Trigger>Ext.jl`, with the module declared inside. |
| Add methods only, qualified to the core (`function Montage.montage(…)`). | The new `ext/` file. |
| Mirror the new trigger in the docs environment. | `docs/Project.toml` `[deps]` and `[compat]`, plus the `EXTENSIONS` list in `docs/make.jl`. |

```toml
[weakdeps]
NewDep = "00000000-0000-0000-0000-000000000000"

[extensions]
MontageNewDepExt = "NewDep"
```

!!! tierdev
    An `[extensions]` value may be a list, and a multi-package extension loads only when every
    one of them is present — `MontageCairoMakiePCMMExt = ["CairoMakie", "PhysiCellModelManager",
    "PhysiCellOutput"]`. Because PhysiCellModelManager depends on PhysiCellOutput, loading PCMM
    alongside Montage activates both PhysiCell extensions at once.

    `ext/MontagePhysiCellModelManagerExt.jl` is the worked example of the shape to copy: 138
    lines, one helper that maps an id to an output folder, and methods that wrap the result in a
    `PhysiCellOutput` handle and forward every other keyword untouched. Everything a PhysiCell
    reader needs is one layer down. When an adapter starts parsing output itself, the logic
    belongs in the extension it delegates to.

    If a helper has to be reachable from an extension that cannot `using` the one defining it,
    declare it in core — with no methods when nothing in core calls it, as `_cellTypeLegend` does,
    or with a strictly more general fallback when core needs a graceful error, as
    `_recordSVGMovie` does.

## Internal reference

The unexported helpers named above, from the core and from each extension.

```@autodocs
Modules = [Montage]
Filter = t -> !(t in (Montage.Panel, Montage.MontageSpec, Montage.montage, Montage.storyboard, Montage.tableau, Montage.record))
```

```@autodocs
Modules = [Main.MontageMovieExt, Main.MontagePhysiCellOutputExt, Main.MontagePhysiCellModelManagerExt, Main.MontageCairoMakieExt, Main.MontageCairoMakiePhysiCellOutputExt, Main.MontageCairoMakiePCMMExt]
Filter = t -> !(t isa Function && nameof(t) in (:montage, :storyboard, :tableau, :record))
```
