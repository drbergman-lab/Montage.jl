```@meta
CurrentModule = Montage
```

# [Movies](@id movies-page)

A movie is the same composition as a still, given frames instead of a single image: you build the composition with a verb, and what the content is decides whether it renders a picture or a video.

!!! tierbrief
    Two verbs animate. [`montage`](@ref) turns into a movie when its panels carry frame
    sequences; [`tableau`](@ref) turns into a movie when its data source spans several
    timepoints. [`storyboard`](@ref) never animates — it is the filmstrip, laid out in
    space instead of time.

!!! tierfull
    There is no `movie=true` keyword and no `montage_movie`/`montage_gif` companion
    function. A keyword would have to be repeated on every verb, and a companion function
    would duplicate every verb's argument list; both leave render-only options such as
    `scale` and `framerate` with nowhere natural to live. Instead a verb builds a
    composition and rendering is a separate step — implicit in the one-call form, explicit
    in [`record`](@ref).

## Montage of movies

Give each panel a `Vector` of frame paths instead of one path, and [`montage`](@ref) writes a video.

!!! tierbrief
    The renderer lives in a package extension: `using Rsvg, Cairo, FFMPEG` loads it.
    Without those three, building the composition still works and only the render step
    errors, with a message naming them.

!!! tierfull
    Panels play in lockstep: frame `t` of the movie is the ordinary stitched grid of every
    panel's `t`-th frame. Frames are matched **by index**, not by simulation time, and the
    movie is truncated to the shortest sequence — a warning reports the per-panel counts
    when they differ. Every panel must carry a sequence; mixing a single-image panel into
    an animated montage is an error rather than a frozen tile.

    The default `output` follows the content: `montage.mp4` once any panel is animated,
    `montage.svg` otherwise. Writing refuses to clobber an existing file unless you pass
    `overwrite=true`.

```julia
using Montage, Rsvg, Cairo, FFMPEG

montage([Panel(["a/snapshot1.svg", "a/snapshot2.svg", "a/snapshot3.svg"]; title="A"),
         Panel(["b/snapshot1.svg", "b/snapshot2.svg", "b/snapshot3.svg"]; title="B")];
        output="compare.mp4", framerate=15)
```

### Rendering in two steps

Pass `output=nothing` and the movie is not rendered: you get a [`MontageSpec`](@ref), which [`record`](@ref) turns into a video whenever you like.

!!! tierbrief
    [`record`](@ref) takes `framerate` and `overwrite` just as the one-call form does, plus
    the one option only it has: `scale`, the rasterization factor. `scale=2` renders every
    frame at twice the composition's nominal pixel size, which is what you want when a
    300 px panel is going onto a projector; it costs encode time and file size and nothing
    else.

!!! tierfull
    The spec carries the panels, the frame count, the grid geometry and the legend, so
    rendering it needs nothing back from the verb — only the frame files its panels name,
    which are read as each frame is composed. A legend supplied as a *file* is read into
    the spec at that moment rather than re-read per frame, and the same legend is drawn into
    every frame — it cannot flicker, and it cannot disappear because a category is absent
    from one timepoint.

    Each panel's `transform` comes along too (see [`Panel`](@ref)). One function edits every
    frame, which suits a time-independent edit like dropping a cell type; a `Vector` of
    functions the same length as the frames edits frame `t` with `transform[t]`, which is
    what colouring by a value that changes over time requires.

```julia
frames(dir) = sort(filter(endswith(".svg"), readdir(dir; join=true)))

spec = montage([Panel(frames("a"); title="A"), Panel(frames("b"); title="B")];
               output=nothing)
record(spec, "compare.mp4"; framerate=24, scale=2)
```

!!! tierdev
    `montage` builds the spec in `Montage._montageSpec` (`src/movie.jl`), which validates the
    panels and resolves the legend; `Montage._svgFrame(spec, t)` composes one frame by
    re-entering the same `_svgGrid` the still path uses, with each panel's `t`-th frame and
    `Montage._frameTransform(p.transform, t)`. `record` itself does only the non-clobber
    check (`Montage._assertWritable`) and delegates to `Montage._recordSVGMovie`, whose
    fallback method in `src/movie.jl` only errors; the real method arrives with
    `MontageMovieExt` (`ext/MontageMovieExt.jl`).

!!! tierjournal "2026-07-21 — record(spec, path) rather than a movie= keyword"
    A verb builds a composition; a separate entry point animates it. Rejected a `movie=`
    keyword on each verb and rejected `_movie`/`_gif` variants: both spread the same
    decision across every verb's signature, and neither leaves anywhere to put render-only
    options like `scale`.

## How a frame is made

The container comes from the path's extension.

!!! tierbrief
    Each timepoint is composed as an ordinary stitched montage SVG, rasterized to a PNG
    through Rsvg and Cairo, and the resulting sequence is encoded by FFMPEG. `.gif` is
    written straight by FFMPEG; anything else is encoded as H.264 with `yuv420p` pixels.

!!! tierfull
    Because each frame is the source SVGs stitched and then rasterized, the movie keeps
    their styling exactly — for PhysiCell output, the same cell colours, outlines and text
    its own renders carry. Nothing is re-plotted, so nothing can drift between a still
    montage and the movie of the same runs.

    `scale` multiplies the rasterization only. The composition's geometry — panel width,
    padding, title band, legend — is fixed in the spec, so a scaled movie is the same figure
    at more pixels, not a different layout.

```julia
record(spec, "compare.gif")                    # FFMPEG's GIF path
record(spec, "compare.mp4"; scale=2)           # H.264, yuv420p
record(spec, "compare.mp4"; overwrite=true)    # replace an existing file
```

!!! tierdev
    `MontageMovieExt._rasterizeSVG` rounds the raster up to even width and height (yuv420p
    encoders reject odd dimensions) and paints a white backdrop first, since an ARGB32
    surface starts transparent and the even-dimension padding would otherwise show. Frames
    are written to a `mktempdir` that a `finally` removes whether or not the encode
    succeeds.

!!! tierjournal "2026-07-21 — SVG frames plus FFMPEG for montage movies"
    Rasterizing each stitched frame through Rsvg/Cairo and encoding with FFMPEG preserves
    PhysiCell's own styling exactly. Rejected rebuilding the grid in Makie for this path: it
    would redraw renders that already exist, and it would pull the Makie stack into the most
    common movie.

## Tableau movies

A [`tableau`](@ref) animates when its data source covers several timepoints — for PhysiCell output, `index=:all` or a range of snapshot indices.

!!! tierbrief
    This path needs `using CairoMakie` plus a data door: `PhysiCellOutput` for an output
    folder, `PhysiCellModelManager` for a simulation id. The whole scene animates — the cell
    layer and every substrate heatmap together — and the result must go to a file in a video
    container, so `output=nothing` is an error here.

!!! tierfull
    Each substrate's colorscale is fixed across the movie from that substrate's minimum and
    maximum over every frame, so a colour means one concentration from the first frame to
    the last. The cell layer is stabilised the same way: a categorical colouring draws the
    union of values seen in any frame, in a fixed order, so the legend and the colours never
    reshuffle; a continuous colouring gets one globally fixed colorrange, computed after
    filtering. Between frames only the data and the timestamp in the focal panel's title
    change, never the axis limits, the legend or the colorbars.

```julia
using Montage, CairoMakie, PhysiCellOutput

seq = PhysiCellSequence("path/to/output")
tableau(seq; index=:all, output="scene.mp4", framerate=15)
tableau(seq; index=0:5:120, substrates=["oxygen"], output="oxygen.mp4")
```

!!! tierdev
    `_tableauMovie` in `ext/MontageCairoMakiePhysiCellOutputExt.jl` loads every requested
    snapshot up front, builds the figure once through the generic
    `tableau(focal, satellites; output=nothing)` with `Observable`s behind the heatmaps, the
    scatter and the focal title, then drives `CairoMakie.record`. In the continuous case the
    positions and the colour values travel in a single `Observable` holding both: updating
    two would leave one frame where the vectors have different lengths.

## Two engines, one idea

|  | montage movie | tableau movie |
|---|---|---|
| Source | finished SVG renders, stitched | data, re-plotted |
| Engine | Rsvg + Cairo rasterization, FFMPEG encode | `Makie.record` |
| Load | `using Rsvg, Cairo, FFMPEG` | `using CairoMakie`, plus `PhysiCellOutput` or `PhysiCellModelManager` |
| Entry point | [`record`](@ref) on a [`MontageSpec`](@ref) | [`tableau`](@ref) with a multi-timepoint `index` |

!!! tierfull
    The split follows from what each verb composes. A montage assembles renders that already
    exist, so the cheapest correct movie is to keep assembling them and hand the frames to an
    encoder — pulling in a plotting stack would only redraw finished pictures. A tableau has
    no finished render to assemble: it draws the scatter and the heatmaps itself from the
    cells and substrate tables, so animating it means holding that figure and swapping its
    data, which is exactly `Makie.record`.

    One consequence is worth knowing before you choose: a montage movie is available with no
    Makie stack loaded, and a tableau movie is the only path that gives you real heatmaps and
    colorbars. See [Extensions](@ref extensions-page) for what each set of packages unlocks.

## Driving movies from simulations

With `PhysiCellModelManager` loaded, both movie paths take simulation ids directly.

```julia
using Montage, PhysiCellModelManager, Rsvg, Cairo, FFMPEG

montage(Simulation, [1, 2, 3]; index=:all, output="compare.mp4", framerate=15)
```

Snapshot selection, cell filtering, colouring and the automatic cell-type legend are covered in [PhysiCell simulations](@ref physicell-page).
