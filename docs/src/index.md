```@meta
CurrentModule = Montage
```

# Montage.jl

Montage composes visualizations — PhysiCell's own renders, or any SVGs you can point it at — into deliberately structured composite figures and movies.

## The three verbs

| Verb | Use it to… | Looks like |
|------|------------|------------|
| [`montage`](@ref) | **compare** like-for-like across many things | a uniform grid of equal panels |
| [`storyboard`](@ref) | show **one thing evolving over time** | an ordered, static filmstrip |
| [`tableau`](@ref) | show how **heterogeneous parts of one state relate** spatially | a focal panel ringed by satellites |

!!! tierbrief
    A real `montage` is the final state of every simulation in a batch, side by side in one
    grid. A real `storyboard` is one simulation's time course, four frames left to right,
    each titled with its timestamp. A real `tableau` is one simulation at one moment: the
    cell layer centred, each substrate's heatmap and colorbar ringed around it, every axis
    on the same spatial extent.

    Still or animated is a separate choice from which verb you reach for. `montage` and
    `tableau` each render a still figure or a movie; `storyboard` is static by design,
    because it *is* the filmstrip.

!!! tierfull
    One general `compose(panels; layout)` could draw all three shapes, so three verbs
    instead of one layout argument is a deliberate cost. The shape is not the point — the
    claim is. A grid of equal cells says *these are comparable*; a left-to-right strip says
    *read me in order*; a centred panel with satellites says *these all describe one state*.
    Naming the claim makes it the thing you choose first, and it lets each verb take the
    defaults that claim implies: `montage` grids near-square, `storyboard` stays on one row
    and puts timestamps in its titles, `tableau` shares one spatial extent across every axis.

    The two movie paths are built differently — a montage movie stitches one SVG per
    timepoint and hands the rasterized frames to FFMPEG, while a tableau movie is recorded by
    Makie — but the choice reads the same at the call site. Panels carrying a single image
    each give a still; panels carrying frame sequences give a movie. See [Movies](@ref movies-page).

## Installation

!!! tierbrief
    The registry also carries PhysiCellModelManager.jl and PhysiCellOutput.jl, so you add it
    once and can then install any of the three.

```julia-repl
pkg> registry add https://github.com/drbergman-lab/BergmanLabRegistry

pkg> add Montage
```

## Quick start

!!! tierbrief
    A [`Panel`](@ref) is one cell of a composition: some content, plus an optional title
    drawn above it. Every verb writes its result by default — pass `output=nothing` to skip
    the write and just take the result, and `overwrite=true` to write over a file that is
    already there.

!!! tierfull
    Cells are uniform and sized from the largest aspect ratio among the panels, so nothing clips, and
    each panel's intrinsic size is parsed out of its own SVG rather than assumed. A title
    band is reserved for the whole grid only when at least one panel is titled, so an
    untitled composition wastes no vertical space. What comes back is a real SVG document
    whose titles and legends are live `<text>`, which keeps the figure editable in
    Illustrator or PowerPoint.

```@setup demo
using Montage
struct SVGFigure
    svg::String
end
function Base.show(io::IO, ::MIME"text/html", f::SVGFigure)
    body = replace(f.svg, r"^<\?xml.*?\?>\s*"s => "")      # inline SVG needs no XML prolog
    print(io, replace(body, "<svg " => """<svg style="max-width: 100%; height: auto;" """; count = 1))
end
dir = mktempdir()
disc(colour) = """<svg width="120" height="120" xmlns="http://www.w3.org/2000/svg"><circle cx="60" cy="60" r="50" fill="$colour"/></svg>"""
a, b = joinpath(dir, "a.svg"), joinpath(dir, "b.svg")
write(a, disc("tomato"))
write(b, disc("steelblue"))
```

```@example demo
svg = montage([Panel(a; title="A"), Panel(b; title="B")]; output=nothing)
SVGFigure(svg) # hide
```

```julia
storyboard([Panel("t0.svg"; title="t = 0"),   Panel("t1.svg"; title="t = 120"),
            Panel("t2.svg"; title="t = 240"), Panel("t3.svg"; title="t = 360")];
           output="timecourse.svg")
```

## A light core, extensions for the rest

!!! tierbrief
    The core does the stitching and nothing else: it reads SVG documents as text, nests them
    in a grid, and writes one SVG back out, with no plotting stack underneath. Everything
    heavier arrives as a package extension, which Julia activates the moment the packages it
    names are loaded. Movies come with `Rsvg`, `Cairo` and `FFMPEG`, which rasterize each
    stitched frame and encode it. [`tableau`](@ref) comes with CairoMakie, which it needs for
    real axes, heatmaps and colorbars — it re-plots from data rather than stitching renders.
    PhysiCell support comes with PhysiCellOutput, for output folders, and
    PhysiCellModelManager, for simulation ids. [Extensions](@ref extensions-page) has the full table.

```julia
using Montage                  # montage and storyboard, stitching SVGs
using Rsvg, Cairo, FFMPEG      # montage movies
using CairoMakie               # tableau, in its data-agnostic form
using PhysiCellModelManager    # drive any verb from simulation ids
```

## PhysiCell simulations

!!! tierbrief
    Montage grew up in the PhysiCell ecosystem, and the verbs know how to read a run.
    `using PhysiCellModelManager, Montage` is all it takes to drive them from simulation
    ids: PhysiCellModelManager depends on PhysiCellOutput, so both PhysiCell extensions
    activate together and ids resolve to output folders for you. Working straight from
    output folders instead, `using PhysiCellOutput` gives the same verbs on a
    `PhysiCellSequence` or a `PhysiCellSnapshot`, with no PhysiCellModelManager in sight.
    [PhysiCell simulations](@ref physicell-page) covers cell-type legends, filtering, colouring cells by a
    data column, and the `index` rule that decides still versus movie.

```julia
using PhysiCellModelManager, Montage

montage(Simulation, simulationIDs())    # every simulation's final state, in one grid
storyboard(Simulation, 32)              # simulation 32's time course, four frames
```

## Manual

```@contents
Pages = ["man/montage.md", "man/storyboard.md", "man/tableau.md",
         "man/movies.md", "man/physicell.md", "man/extensions.md"]
Depth = 1
```
