```@meta
CurrentModule = Montage
```

# [Montage](@id montage-page)

[`montage`](@ref) arranges homogeneous panels into a uniform titled grid — the verb for comparing like-for-like across many things, such as the final state of every simulation in a batch.

!!! tierfull
    The grid is stitched, not re-plotted. Each panel's SVG is inlined into the
    composition as a nested, positioned `<svg>` element, so the result stays lossless
    vector at any size and every panel keeps the styling of whatever drew it. Nothing
    is rasterized and no plotting library is involved: a still `montage` needs no
    package beyond Montage itself.

!!! tierjournal "2026-07-21 — SVG string-stitching as the core default"
    The core stitches nested `<svg>` elements rather than re-plotting, which keeps the
    figure lossless vector, keeps PhysiCell's own styling exactly, and keeps the package
    free of any heavy dependency. Decided against making CairoMakie the default backend
    for this verb: it would force the whole Makie stack on every user for a grid of
    images it would only rasterize or redraw. The `backend` keyword and its
    `MakieBackend` selector remain as scaffolding; `montage` is SVG-only.

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
function fixture(name, colour)
    path = joinpath(dir, name * ".svg")
    write(path, disc(colour))
    return path
end
a = fixture("a", "tomato")
b = fixture("b", "steelblue")
reps = [fixture("r$i", c) for (i, c) in enumerate(
    ["tomato", "salmon", "steelblue", "skyblue", "seagreen", "darkseagreen"])]
```

## Panels

!!! tierbrief
    A [`Panel`](@ref) is one cell of the composition: some content, plus an optional
    `title` drawn above it. Pass a `Vector{Panel}`, or a loose vector of raw contents,
    which is wrapped as untitled panels.

!!! tierfull
    For the SVG backend a panel's content is a path to an SVG file. The file is read
    once, inlined, and scaled to its cell by a `viewBox` — so it fits instead of
    clipping, and it scales instead of pixellating. Its intrinsic size is parsed out of
    the root `<svg>` tag, never assumed, so panels rendered at different sizes compose
    fine.

    An empty title is the default, and a composition where no panel carries one
    reserves no title band at all.

```@example demo
svg = montage([Panel(a; title="A"), Panel(b; title="B")]; output=nothing)
SVGFigure(svg) # hide
```

!!! tierdev
    The `:svg` backend requires each panel's content to be an `AbstractString` path to
    an existing file, and errors otherwise; there is no rendering fallback. A still
    panel's `transform` must be a single function — a `Vector` is the per-frame movie
    form and is rejected with a message saying so.

## The grid

!!! tierbrief
    Panels fill the grid row-major. `ncols` sets the number of columns and defaults to
    the near-square `ceil(sqrt(n))`.

!!! tierfull
    Every cell is the same size: `panel_width` (default 300) px wide, and tall enough
    for the *largest aspect ratio among the panels*, so no panel overflows or clips.
    `pad` (default 12) px separates the cells and frames the figure. A title band of
    `title_height` (default 34) px is reserved for the whole grid only if at least one
    panel carries a title, so an all-untitled composition wastes no vertical space.

    Set `ncols` when the comparison itself has a shape. Listing panels row-major with
    `ncols` equal to the number of replicates puts one condition per row, which is the
    figure you were going to assemble by hand anyway.

```@example demo
titles = ["control 1", "control 2", "low dose 1", "low dose 2", "high dose 1", "high dose 2"]
svg = montage([Panel(p; title=t) for (p, t) in zip(reps, titles)];
              ncols=2, panel_width=180, output=nothing)
SVGFigure(svg) # hide
```

!!! tierdev
    The geometry lives in one place, `_svgGrid` in `src/svg_backend.jl`, which
    [`montage`](@ref) and [`storyboard`](@ref) share. The only difference between the
    two verbs is the column count they hand it: `ceil(sqrt(n))` against `n`.

!!! tierjournal "2026-09-21 — ncols over an explicit Layout type"
    `ncols` alone, defaulting to the near-square `ceil(sqrt(n))`, was enough to express
    the grid shape people actually ask for (conditions by replicates, panels listed
    row-major). Rejected a richer layout object: it would have to be threaded through
    stills, `MontageSpec` and every movie frame for a shape that one integer already
    names.

## Output

!!! tierbrief
    `montage` writes `./montage.svg` and *also* returns the composed SVG string. Point
    `output` somewhere else, or pass `output=nothing` to get the string without writing
    anything. Writing an existing path errors unless `overwrite=true`.

```julia
montage(panels)                                   # ./montage.svg, and returns the SVG
montage(panels; output="figures/batch.svg", overwrite=true)
svg = montage(panels; output=nothing)             # compose only, write nothing
```

## Legends

!!! tierbrief
    `legend` says **what** to draw; `legend_position` says **where** it goes. They are
    independent, so any legend content can take any placement.

!!! tierfull
    `legend` takes `nothing` (the default, no legend), a vector of `(label, colour)`
    entries to draw, a path or SVG string to nest as-is, or a function that draws one.
    Drawn entries come out as flat `<circle>` and `<text>` elements rather than a nested
    `<svg>`, which is what lets you open the figure in Illustrator or PowerPoint and
    nudge the legend around. `legend_font_size` sets their size and defaults to the
    panel-title size, so the two match; a drawn legend holds that size and wraps to fit
    whatever space it is given.

    `legend_position` takes `:auto`, `:bottom`, `:top`, or an explicit `(row, col)` or
    `(row, col, span)` cell. `:auto` prefers the free cells trailing the last row when
    the layout has any — seven panels in a three-wide grid leave two — so the legend
    costs no space at all; with no spare cells it falls back to a full-width band below.

```@example demo
svg = montage([Panel(a; title="A"), Panel(b; title="B")];
              legend=[("tumour", "grey"), ("immune", "seagreen")],
              legend_position=:bottom, output=nothing)
SVGFigure(svg) # hide
```

!!! tierdev
    The draw-function form has the signature `(x, y, avail_w) -> (fragment, w, h)` and
    is called more than once — to measure, then to emit — so it must be pure. It is how
    the PhysiCell extension supplies a colorbar that the core knows nothing about.

## Editing panel contents: the transform seam

!!! tierbrief
    `Panel(content; transform=f)` runs `f`, an `SVG text -> SVG text` function, on that
    panel's markup just before it is placed.

!!! tierfull
    Constructing a `Panel` does nothing on its own — the transform runs when the grid is
    built, on the text read from the file, so the source file is never modified. The
    default `identity` returns the very same object, which makes the untransformed path
    byte-identical to one with no transform support at all. Anything the transform
    injects is written in the panel's own coordinate system and scales with it, because
    each panel is nested with its intrinsic `viewBox`.

    For a movie panel, `transform` can be a single function applied to every frame, or a
    `Vector` of functions the same length as the frames, in which case frame `t` is
    edited by `transform[t]`. The per-frame form exists because some edits depend on the
    timepoint: colouring cells by a data value has to map each frame from that
    snapshot's own values.

```julia
# stamp a scale bar into each panel on its way into the grid
scalebar(svg) = replace(svg, r"</svg>\s*$"s =>
    """<rect x="40" y="940" width="200" height="10" fill="black"/></svg>""")

montage([Panel("control/final.svg"; title="control", transform=scalebar),
         Panel("treated/final.svg"; title="treated", transform=scalebar)])
```

## Comparing dynamics

!!! tierbrief
    Give a panel a `Vector` of frame paths instead of one path and the same call
    produces a movie: every panel plays its frames in lockstep, aligned by index and
    truncated to the shortest sequence. See [Movies](@ref movies-page) for the rendering path,
    `framerate`, `scale` and [`record`](@ref).

```julia
using Rsvg, Cairo, FFMPEG    # the movie extension

montage([Panel(control_frames; title="control"),
         Panel(treated_frames; title="treated")];
        output="compare.mp4", framerate=15)
```

## PhysiCell simulations

!!! tierbrief
    With PhysiCellOutput or PhysiCellModelManager loaded, `montage` takes output folders
    (as a `PhysiCellSequence`) and simulation ids directly, and gains cell-type filtering,
    colouring cells by a data column, and an automatic legend read from each run's own
    `legend.svg`.
    [PhysiCell simulations](@ref physicell-page) covers all of it.

```julia
using PhysiCellModelManager, Montage

montage(Simulation, [1, 2, 3]; index=:final)
```
