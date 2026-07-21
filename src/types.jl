# Core types shared by every composition verb and backend.
#
# These are defined in the core (not an extension) so that package extensions
# — `MontageCairoMakieExt`, `MontagePhysiCellModelManagerExt` — can add methods
# dispatching on them. Extensions may only add methods to functions/types the
# core already owns.

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
