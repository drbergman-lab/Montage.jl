# The `storyboard` verb: show one thing evolving over time.
#
# A 1-D ordered sequence of frames stitched into a single *static* figure (a filmstrip for
# a poster or paper). Movies are `montage`'s / `tableau`'s job — storyboard is deliberately
# static. Each frame's title is exposed so callers can label it with a timestamp.

"""
    storyboard(panels; backend=:svg, ncols=length(panels), panel_width=300,
               title_height=34, pad=12, legend=nothing, legend_file=nothing,
               legend_font_size=22, output="storyboard.svg", overwrite=false)

Stitch an **ordered** sequence of `panels` into a single static figure — the verb for
showing one subject evolving over time (e.g. a simulation's snapshots left to right).

Unlike [`montage`](@ref) (an unordered `ceil(sqrt(n))` grid), `storyboard` lays panels out
in reading order and defaults to a **single row** (`ncols = length(panels)`); set `ncols`
to wrap the strip into that many columns while preserving time order.

# Arguments
- `panels`: a `Vector{Panel}`, or a loose vector of raw contents (each wrapped as an
  untitled [`Panel`](@ref)). Each panel's content is a single SVG path — a frame sequence
  is not allowed (storyboard is static; use `montage` for movies). Titles are where
  timestamps go.

# Keyword Arguments
- `backend::Symbol=:svg`: `:svg` (default) or `:makie` (requires `using CairoMakie`).
- `ncols::Integer=length(panels)`: columns in the strip; the default is a single row.
- `panel_width`, `title_height`, `pad`, `legend`, `legend_file`, `legend_font_size`: as in
  [`montage`](@ref). A single-row strip has no spare grid cell, so an `:auto` legend lands in a
  full-width band below the frames.
- `output::Union{Nothing,AbstractString}="storyboard.svg"`: where to write the SVG (cwd by
  default); errors if it exists unless `overwrite=true`. `output=nothing` returns the SVG
  string without writing.
- `overwrite::Bool=false`: allow writing over an existing `output` file.

# Returns
The composed SVG document as a `String` (written to `output` unless `output=nothing`).

# Examples
```julia
using Montage

# A four-frame time strip with timestamp titles → writes ./storyboard.svg
storyboard([Panel("t0.svg"; title="t = 0"),   Panel("t1.svg"; title="t = 120"),
            Panel("t2.svg"; title="t = 240"), Panel("t3.svg"; title="t = 360")])
```
"""
function storyboard(panels; backend::Symbol=:svg, ncols::Integer=length(panels),
                    panel_width::Real=300, title_height::Real=34, pad::Real=12,
                    legend=nothing, legend_file=nothing, legend_font_size::Real=_TITLE_FONT_SIZE,
                    output::Union{Nothing,AbstractString}="storyboard.svg", overwrite::Bool=false)
    ps = _asPanels(panels)
    any(_isAnimated, ps) &&
        error("storyboard is static — each panel must be a single image, not a frame sequence; use `montage` for movies")
    legend_svg, legend_position = _normalizeLegend(legend, legend_file)
    return _storyboard(montageBackend(backend), ps; ncols, panel_width, title_height, pad,
                       legend_svg, legend_position, legend_font_size, output, overwrite)
end

# --- :svg backend (core) ---
function _storyboard(::SVGBackend, panels::AbstractVector{Panel};
                     ncols, panel_width, title_height, pad,
                     legend_svg, legend_position, legend_font_size, output, overwrite)
    svg = _svgGrid(panels; ncols, panel_width, title_height, pad,
                   legend_svg, legend_position, legend_font_size)
    return _writeSVG(svg, output, overwrite)
end

# --- other backends (e.g. :makie, added later) — abstract-type fallback, no overwrite ---
function _storyboard(::MontageBackend, panels::AbstractVector{Panel}; kwargs...)
    error("the :makie backend requires CairoMakie — run `using CairoMakie` to load it")
end
