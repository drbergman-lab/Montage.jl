# Core types shared by every composition verb and backend.
#
# These are defined in the core (not an extension) so that package extensions
# — `MontageCairoMakieExt`, `MontagePhysiCellModelManagerExt` — can add methods
# dispatching on them. Extensions may only add methods to functions/types the
# core already owns.

"""
Font size (px) of the bold panel titles drawn by `_svgGrid`.

Also the default size for a **drawn** legend's text, so legend and titles match. (A legend given
as an SVG *file* is not rescaled to it — that one is placed at its natural size.) Lives here rather
than in `svg_backend.jl` because `MontageSpec`'s old-arity constructor defaults to it, and
`types.jl` is included first.
"""
const _TITLE_FONT_SIZE = 22

"""
    Panel(content; title="", transform=identity)
    Panel(content, title)

One cell of a composition: some `content` plus an optional `title` drawn above it.

# Arguments
- `content`: what to draw. For the SVG backend this is a path to an SVG file
  (`AbstractString`). Future Makie-backed content (a plotting callback + data) also
  lands here.
- `title::AbstractString`: text drawn in a band above the content. An empty title
  (the default) means *no* title band is reserved for this panel — an all-untitled
  composition has no wasted vertical space.
- `transform`: a function applied to this panel's SVG text before it is placed —
  `SVG text -> SVG text`. The seam for editing a panel's contents without re-rendering it: the
  PhysiCell extension uses it to drop or recolour cells. `identity` (the default) is free — it
  returns the very same object, so the output is byte-identical to no transform at all.

  A **movie** panel's content is a list of frames, and `transform` can match it one-for-one:

  - one function — applied to every frame (e.g. "drop the `nk` cells", which does not depend on
    time);
  - a list of functions, the same length as the frames — then frame `t` is edited by
    `transform[t]`.

  The per-frame form exists because some edits *do* depend on the timepoint: colouring cells by a
  data value needs each frame mapped from that snapshot's own values, so each frame needs its own
  function.

# Examples
```julia
Panel("output/final.svg"; title="Sim 1")
Panel("output/final.svg")                                  # untitled
Panel("output/final.svg"; transform = s -> replace(s, "red" => "blue"))
```
"""
struct Panel
    content::Any
    title::String
    transform::Any
end
Panel(content, title::AbstractString) = Panel(content, String(title), identity)   # coerce SubString etc.
Panel(content; title::AbstractString="", transform=identity) =
    Panel(content, String(title), transform)

"""
    _frameTransform(transform, t) -> Function

The transform for frame `t`: a `Vector` of transforms is indexed, anything else (a plain function)
is used as-is for every frame.
"""
_frameTransform(transform::AbstractVector, t::Integer) = transform[t]
_frameTransform(transform, ::Integer) = transform

"""
    montageBackend(sym::Symbol) -> MontageBackend

Map a user-facing `backend` keyword (`:svg`, `:makie`) to its selector type.
Unknown symbols throw.
"""
abstract type MontageBackend end

"""SVG string-stitch backend — the core default. Lossless vector, static only."""
struct SVGBackend <: MontageBackend end

"""
CairoMakie backend — real heatmaps/colorbars, `tableau`, and movies. Its methods
live in `MontageCairoMakieExt` and are available only after `using CairoMakie`.
"""
struct MakieBackend <: MontageBackend end

function montageBackend(sym::Symbol)
    sym === :svg && return SVGBackend()
    sym === :makie && return MakieBackend()
    error("unknown backend $(repr(sym)); expected :svg or :makie")
end

"""
    _asPanels(items) -> Vector{Panel}

Normalize a loose collection into `Vector{Panel}`. Accepts a vector of `Panel`s
(returned as-is) or a vector of raw contents (each wrapped as an untitled `Panel`).
"""
_asPanels(panels::AbstractVector{Panel}) = collect(panels)
_asPanels(items::AbstractVector) = Panel[item isa Panel ? item : Panel(item) for item in items]

"""
    _isAnimated(panel) -> Bool

A panel is *animated* when its content is a sequence of per-timepoint frames (a
`Vector`) rather than a single static image. Animated panels turn a `montage` into a
[`MontageSpec`](@ref) that [`record`](@ref) can render as a movie.
"""
_isAnimated(p::Panel) = p.content isa AbstractVector

"""
    MontageSpec

A movie-able composition: a uniform grid of frame-sequence `panels` (each panel's
content is a `Vector` of per-timepoint frame paths), a common `nframes` count, and the
grid layout parameters. Built by [`montage`](@ref) when its panels are animated, and
consumed by [`record`](@ref).

Frames are aligned by index and truncated to the shortest sequence (see `nframes`).

The `legend_svg`/`legend_position`/`legend_font_size` fields carry the composition's legend
(see `_svgGrid`) so every rendered frame draws the same one — a legend that would otherwise
flicker or vanish mid-movie. The five-argument constructor omits them (no legend).
"""
struct MontageSpec
    panels::Vector{Panel}
    nframes::Int
    panel_width::Float64
    title_height::Float64
    pad::Float64
    legend_svg::Any                     # nothing | (label, color) entries | an SVG path/string
    legend_position::Any
    legend_font_size::Float64
end

# Old-arity constructor — keeps hand-built specs (and any caller predating legends) working.
MontageSpec(panels, nframes, panel_width, title_height, pad) =
    MontageSpec(panels, nframes, panel_width, title_height, pad, nothing, :auto, _TITLE_FONT_SIZE)

Base.show(io::IO, spec::MontageSpec) =
    print(io, "MontageSpec($(length(spec.panels)) panels × $(spec.nframes) frames)")
