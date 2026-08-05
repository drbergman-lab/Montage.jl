# Core types shared by every composition verb and backend.
#
# These are defined in the core (not an extension) so that package extensions
# — `MontageCairoMakieExt`, `MontagePhysiCellModelManagerExt` — can add methods
# dispatching on them. Extensions may only add methods to functions/types the
# core already owns.

"""
Font size (px) of the bold panel titles drawn by `_svgGrid`.

Also the default target for legend scaling: a legend is scaled so *its* text renders at this
size, matching the title text. Lives here (not in `svg_backend.jl`) because `MontageSpec`'s
old-arity constructor defaults to it, and `types.jl` is included first.
"""
const _TITLE_FONT_SIZE = 22

"""
    Panel(content; title="")
    Panel(content, title)

One cell of a composition: some `content` plus an optional `title` drawn above it.

# Arguments
- `content`: what to draw. For the SVG backend this is a path to an SVG file
  (`AbstractString`). Future Makie-backed content (a plotting callback + data) also
  lands here.
- `title::AbstractString`: text drawn in a band above the content. An empty title
  (the default) means *no* title band is reserved for this panel — an all-untitled
  composition has no wasted vertical space.

# Examples
```julia
Panel("output/final.svg"; title="Sim 1")
Panel("output/final.svg")            # untitled
```
"""
struct Panel
    content::Any
    title::String
end
Panel(content, title::AbstractString) = Panel(content, String(title))   # coerce SubString etc.
Panel(content; title::AbstractString="") = Panel(content, String(title))

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
