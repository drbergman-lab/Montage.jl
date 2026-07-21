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
  SVG file.

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
For `backend=:svg`, the composed SVG document as a `String` (and writes it to `output`
if given).

# Examples
```julia
using Montage

# Titled panels
svg = montage([Panel("a/final.svg"; title="A"), Panel("b/final.svg"; title="B")])

# Loose, untitled — no title band, no wasted white space
montage(["a/final.svg", "b/final.svg"]; output="grid.svg")
```
"""
function montage(panels; backend::Symbol=:svg, panel_width::Real=300,
                 title_height::Real=34, pad::Real=12, output=nothing)
    return _montage(montageBackend(backend), _asPanels(panels);
                    panel_width, title_height, pad, output)
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

# --- :makie backend (added by MontageCairoMakieExt) ---
# Core fallback: a helpful error until the extension is loaded.
function _montage(::MakieBackend, panels::AbstractVector{Panel}; kwargs...)
    error("the :makie backend requires CairoMakie — run `using CairoMakie` to load it")
end
