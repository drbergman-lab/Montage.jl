# The `montage` verb: compare like-for-like across many things.
#
# Uniform grid of equal panels. Core implements the :svg backend; the :makie
# backend's method is added by MontageCairoMakieExt (loaded via `using CairoMakie`).

# Does this (possibly loose) panel carry a frame sequence (→ movie) rather than one image?
_looksAnimated(p::Panel) = _isAnimated(p)
_looksAnimated(x) = x isa AbstractVector

# Default output path, in the current directory, keyed to still image vs. movie.
_defaultOutput(panels) = any(_looksAnimated, panels) ? "montage.mp4" : "montage.svg"

"""
    montage(panels; backend=:svg, panel_width=300, title_height=34, pad=12,
            legend=nothing, legend_position=:auto, legend_font_size=<title size>,
            output=<auto: montage.svg | montage.mp4>, overwrite=false, framerate=15)

Compose `panels` into a uniform titled grid — the verb for comparing like-for-like
across many things (e.g. the final state of every simulation in a batch, side by side).

The **panel content decides still image vs. movie**, in one call: if every panel's content
is a single image (an SVG path), the result is a still image; if any panel's content is a
**`Vector` of frame paths** (one per timepoint), every panel plays its frames in lockstep
and the result is a movie (rendered via [`record`](@ref), which needs `using Rsvg, Cairo,
FFMPEG`).

# Arguments
- `panels`: a `Vector{Panel}`, or a loose vector of raw contents (each wrapped as an
  untitled [`Panel`](@ref)). A panel's content is an SVG path (still) or a `Vector` of
  SVG paths (frames of a movie).

# Keyword Arguments
- `backend::Symbol=:svg`: `:svg` (default, built into the core — lossless vector, static)
  or `:makie` (real heatmaps/colorbars; requires `using CairoMakie`).
- `panel_width::Real=300`: displayed width in px of each panel.
- `title_height::Real=34`: px reserved above each panel for its title. The band is
  reserved for the whole grid only if at least one panel is titled.
- `pad::Real=12`: px of padding between and around panels.
- `legend`: **what** legend to draw — `[("label", "color"), …]` entries (drawn as flat circles and
  labels, so they stay editable in Illustrator/PowerPoint), or a path/SVG string to nest as-is.
  `nothing` (the core default) draws none. With PhysiCellOutput or PCMM loaded the default becomes
  `:auto`, which means "take the cell types from the run's own `legend.svg`".
- `legend_position`: **where** it goes — `:auto` (the free cells trailing the last row if the
  layout has any, so the figure does not grow, else a full-width band below), `:bottom`, `:top`,
  or an explicit `(row, col)` / `(row, col, span)` cell. Independent of `legend`, so any content
  can take any placement.
- `legend_font_size::Real`: text size for a drawn legend. Defaults to the panel-title size, so the
  two match. Drawn legends keep this size and **wrap** to fit the space; a nested SVG legend
  instead sits at its natural size, shrunk only if it will not fit.
- `output::Union{Nothing,AbstractString}`: where to write the result, in the current
  directory by default — `montage.svg` for a still image, `montage.mp4` for a movie.
  Errors if the file exists unless `overwrite=true`. Pass `output=nothing` to skip writing
  and return the in-memory result instead.
- `overwrite::Bool=false`: allow writing over an existing `output` file.
- `framerate::Integer=15`: frames per second (movies only).

# Returns
The written path's result: the composed SVG `String` for a still image, or the output path
for a movie. With `output=nothing`, the in-memory object instead — the SVG `String` for a
still image, or a [`MontageSpec`](@ref) for a movie (which you can then hand to
[`record`](@ref) for finer control, e.g. `scale`).

# Examples
```julia
using Montage

# Still image — written to ./montage.svg by default, and returned as a string
svg = montage([Panel("a/final.svg"; title="A"), Panel("b/final.svg"; title="B")])
montage(["a/final.svg", "b/final.svg"]; output="grid.svg")   # or choose a path

# A legend of your own, banded below rather than tucked into a spare cell
montage(["a/final.svg", "b/final.svg"];
        legend=[("tumor", "grey"), ("immune", "green")], legend_position=:bottom)

# Montage of movies: each panel is a frame sequence → one call writes ./montage.mp4
using Rsvg, Cairo, FFMPEG                                    # movie extension
montage([Panel(["a/f1.svg", "a/f2.svg"]; title="A"),
         Panel(["b/f1.svg", "b/f2.svg"]; title="B")]; output="compare.mp4", framerate=15)
```
"""
function montage(panels; backend::Symbol=:svg, panel_width::Real=300,
                 title_height::Real=34, pad::Real=12,
                 legend=nothing, legend_position=:auto, legend_font_size::Real=_TITLE_FONT_SIZE,
                 output::Union{Nothing,AbstractString}=_defaultOutput(panels),
                 overwrite::Bool=false, framerate::Integer=15)
    ps = _asPanels(panels)
    legend_svg = _normalizeLegend(legend)
    if any(_isAnimated, ps)
        # movie: build the spec, then render it (unless output=nothing → return the spec)
        spec = _montageSpec(ps; panel_width, title_height, pad,
                            legend_svg, legend_position, legend_font_size)
        output === nothing && return spec
        return record(spec, output; framerate, overwrite)
    end
    return _montage(montageBackend(backend), ps; panel_width, title_height, pad,
                    legend_svg, legend_position, legend_font_size, output, overwrite)
end

# --- :svg backend (core) ---
function _montage(::SVGBackend, panels::AbstractVector{Panel};
                  panel_width, title_height, pad,
                  legend_svg, legend_position, legend_font_size, output, overwrite)
    svg = _svgGrid(panels; panel_width, title_height, pad,
                   legend_svg, legend_position, legend_font_size)
    return _writeSVG(svg, output, overwrite)
end

"""
    _writeSVG(svg, output, overwrite) -> svg

Write `svg` to `output` (guarded by `_assertWritable`) and return it; if `output` is
`nothing`, return `svg` without writing. Shared by the SVG-backend verbs.
"""
_writeSVG(svg, ::Nothing, overwrite) = svg
function _writeSVG(svg, output::AbstractString, overwrite)
    _assertWritable(output, overwrite)
    mkpath(dirname(abspath(String(output))))
    write(String(output), svg)
    return svg
end

"""
    _assertWritable(path, overwrite)

Throw if `path` exists and `overwrite` is false — the shared non-clobber guard for every
core write (`montage`, `record`).
"""
_assertWritable(path, overwrite) =
    (!overwrite && isfile(String(path))) &&
        error("output $path already exists; pass `overwrite=true` to replace it, or `output=<path>` to write elsewhere")

# --- other backends (e.g. :makie, added by MontageCairoMakieExt) ---
# Catch-all fallback on the ABSTRACT type so an extension can add a concrete
# `_montage(::MakieBackend, …)` method without a method-overwrite warning.
function _montage(::MontageBackend, panels::AbstractVector{Panel}; kwargs...)
    error("the :makie backend requires CairoMakie — run `using CairoMakie` to load it")
end
