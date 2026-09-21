```@meta
CurrentModule = Montage
```

# [Storyboard](@id storyboard-page)

[`storyboard`](@ref) stitches an **ordered** sequence of frames into a single static figure — the filmstrip you put on a poster or in a paper.

```@setup storyboard
using Montage

struct SVGFigure
    svg::String
end
function Base.show(io::IO, ::MIME"text/html", f::SVGFigure)
    body = replace(f.svg, r"^<\?xml.*?\?>\s*"s => "")      # inline SVG needs no XML prolog
    print(io, replace(body, "<svg " => """<svg style="max-width: 100%; height: auto;" """; count = 1))
end

dir = mktempdir()
disc(colour, r) = """<svg width="120" height="120" xmlns="http://www.w3.org/2000/svg"><circle cx="60" cy="60" r="$r" fill="$colour"/></svg>"""
times = 0:120:600
frames = [joinpath(dir, "t$t.svg") for t in times]
for (i, path) in enumerate(frames)
    write(path, disc("seagreen", 8 + 7i))
end
```

## A single row, in reading order

!!! tierbrief
    Pass one panel per frame, oldest first. Panels fill left to right, and each panel's
    `title` is where its timestamp goes.

!!! tierfull
    Order is the whole difference from [`montage`](@ref). A montage compares things that have
    no inherent sequence, so it packs them into a near-square grid; a storyboard is one subject
    over time, so it defaults to a single row (`ncols = length(panels)`) and reading order *is*
    time order. Titles are exposed for exactly this reason: a frame that does not say when it
    was taken leaves the reader counting panels.

    Cells are uniform and sized from the largest aspect ratio among the panels, so frames that differ
    slightly in intrinsic size still line up rather than clip. The title band is reserved once
    for the whole strip, and only if at least one panel carries a title.

```@example storyboard
svg = storyboard([Panel(frames[i]; title = "t = $(times[i])") for i in 1:4]; output = nothing)
SVGFigure(svg) # hide
```

## Wrapping a long strip

!!! tierbrief
    `ncols` sets the number of columns. Panels keep the order you gave them and fill row-major,
    so time runs left to right and then down.

```@example storyboard
svg = storyboard([Panel(frames[i]; title = "t = $(times[i])") for i in eachindex(frames)];
                 ncols = 3, output = nothing)
SVGFigure(svg) # hide
```

## Static by design

!!! tierbrief
    A panel whose content is a vector of frame paths is rejected. To animate one subject's
    frames, hand them to [`montage`](@ref) as a single animated panel instead — see
    [Movies](@ref movies-page).

!!! tierfull
    A filmstrip and a movie are different artefacts, not two renderings of one thing. The strip
    shows every timepoint at once, to be scanned and compared and printed; the movie shows one
    timepoint at a time, to be played. Which of the two you want is a decision about the figure,
    and a verb that quietly produced either one depending on the shape of its argument would
    make that decision invisible at the call site — you would have to inspect the panels to know
    what you were about to get. So `storyboard` commits to the strip and says so loudly.

```julia
storyboard([Panel(frames)])
# ERROR: storyboard is static — each panel must be a single image, not a frame
# sequence; use `montage` for movies

montage([Panel(frames; title = "colony")]; output = "colony.mp4")   # the movie of those frames
```

## Writing the figure

!!! tierbrief
    `storyboard` writes `storyboard.svg` in the current directory and also returns the composed
    SVG as a `String`. Point `output` somewhere else, set it to `nothing` to skip writing
    entirely, and pass `overwrite = true` to replace a file that already exists — without it, an
    existing `output` is an error rather than a silent clobber.

```julia
storyboard(panels)                              # → ./storyboard.svg, and returns the String
storyboard(panels; output = "figs/fig2.svg")    # any other path (directories are created)
storyboard(panels; output = nothing)            # the String only, nothing written
storyboard(panels; overwrite = true)            # replace an existing file
```

## Legends

!!! tierbrief
    `legend` says what to draw and `legend_position` says where, exactly as in [Montage](@ref montage-page).
    The one difference is placement: a single-row strip has no spare grid cell, so
    `legend_position = :auto` falls back to a full-width band under the frames. Wrap the strip
    with `ncols` and any trailing free cells become available again.

```@example storyboard
svg = storyboard([Panel(frames[i]; title = "t = $(times[i])") for i in 1:4];
                 legend = [("colony", "seagreen")], output = nothing)
SVGFigure(svg) # hide
```

## PhysiCell runs

!!! tierbrief
    A storyboard can be built straight from a simulation, which picks the snapshots, titles each
    frame with its time, and takes the cell-type legend from the run itself. Those keywords are
    documented on [PhysiCell simulations](@ref physicell-page).

```julia
using PhysiCellModelManager, Montage

storyboard(Simulation, 1)
```
