# The `montage` verb: compare like-for-like across many things.
#
# Uniform grid of equal panels. Core implements the :svg backend; the :makie
# backend's method is added by MontageCairoMakieExt (loaded via `using CairoMakie`).

"""
    montage(panels; backend=:svg, panel_width=300, title_height=34, pad=12, output=nothing)

Compose `panels` into a uniform titled grid — the verb for comparing like-for-like
across many things (e.g. the final state of every simulation in a batch, side by side).

# Arguments
- `panels`: a `Vector{Panel}`, or a loose vector of raw contents (each wrapped as an
  untitled [`Panel`](@ref)). For the `:svg` backend, a panel's content is a path to an
  SVG file. If a panel's content is instead a **`Vector` of frame paths** (one per
  timepoint), the panel is *animated* and `montage` returns a [`MontageSpec`](@ref) —
  hand it to [`record`](@ref) to write a movie where every panel plays in lockstep.

# Keyword Arguments
- `backend::Symbol=:svg`: `:svg` (default, built into the core — lossless vector, static)
  or `:makie` (real heatmaps/colorbars; requires `using CairoMakie`).
- `panel_width::Real=300`: displayed width in px of each panel.
- `title_height::Real=34`: px reserved above each panel for its title. The band is
  reserved for the whole grid only if at least one panel is titled.
- `pad::Real=12`: px of padding between and around panels.
- `output=nothing`: if a path is given, the composed figure is written there. Returns
  the composition regardless.

# Returns
For static panels on `backend=:svg`, the composed SVG document as a `String` (and
writes it to `output` if given). For animated panels, a [`MontageSpec`](@ref).

# Examples
```julia
using Montage

# Titled panels
svg = montage([Panel("a/final.svg"; title="A"), Panel("b/final.svg"; title="B")])

# Loose, untitled — no title band, no wasted white space
montage(["a/final.svg", "b/final.svg"]; output="grid.svg")

# A montage of movies: each panel is a frame sequence; play them in lockstep
spec = montage([Panel(["a/f1.svg", "a/f2.svg"]; title="A"),
                Panel(["b/f1.svg", "b/f2.svg"]; title="B")])
record(spec, "compare.mp4"; framerate=15)   # requires `using Rsvg, Cairo, FFMPEG`
```
"""
function montage(panels; backend::Symbol=:svg, panel_width::Real=300,
                 title_height::Real=34, pad::Real=12, output=nothing)
    ps = _asPanels(panels)
    if any(_isAnimated, ps)
        # movie-able composition — return a spec for `record`
        return _montageSpec(ps; panel_width, title_height, pad)
    end
    return _montage(montageBackend(backend), ps; panel_width, title_height, pad, output)
end

# --- :svg backend (core) ---
function _montage(::SVGBackend, panels::AbstractVector{Panel};
                  panel_width, title_height, pad, output)
    svg = _svgMontage(panels; panel_width, title_height, pad)
    if output !== nothing
        mkpath(dirname(abspath(String(output))))
        write(String(output), svg)
    end
    return svg
end

# --- other backends (e.g. :makie, added by MontageCairoMakieExt) ---
# Catch-all fallback on the ABSTRACT type so an extension can add a concrete
# `_montage(::MakieBackend, …)` method without a method-overwrite warning.
function _montage(::MontageBackend, panels::AbstractVector{Panel}; kwargs...)
    error("the :makie backend requires CairoMakie — run `using CairoMakie` to load it")
end
