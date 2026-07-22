# Movie composition: turning an animated `montage` into a video.
#
# The default (and, for now, only) rendering path is SVG-frame + FFMPEG: each timepoint
# is the static montage of that timepoint's frames, rasterized and encoded. The heavy
# lifting (rasterize + encode) lives in `ext/MontageMovieExt.jl` (weakdeps Rsvg, Cairo,
# FFMPEG); the core owns the spec, the per-frame SVG builder, and the `record` entry point.

"""
    _montageSpec(panels; panel_width, title_height, pad) -> MontageSpec

Build a [`MontageSpec`](@ref) from animated panels (content is a `Vector` of frame
paths). Frames are aligned by index and truncated to the shortest sequence; a warning
is emitted if the panels have differing frame counts.
"""
function _montageSpec(panels::AbstractVector{Panel}; panel_width, title_height, pad)
    all(_isAnimated, panels) ||
        error("montage movie: every panel must carry a frame sequence (a Vector of frame paths)")
    lens = [length(p.content) for p in panels]
    nframes = minimum(lens)
    nframes == 0 && error("montage movie: at least one panel has no frames")
    if !all(==(nframes), lens)
        @warn "montage movie: panels have differing frame counts; truncating to the shortest" counts=lens nframes
    end
    return MontageSpec(collect(panels), nframes,
                       Float64(panel_width), Float64(title_height), Float64(pad))
end

"""
    _svgFrame(spec::MontageSpec, t::Integer) -> String

Compose the montage SVG for timepoint `t` (1-based) by taking each panel's `t`-th frame
and stitching them with the same grid logic as the static [`montage`](@ref).
"""
function _svgFrame(spec::MontageSpec, t::Integer)
    1 <= t <= spec.nframes || throw(BoundsError(spec, t))
    frame = [Panel(p.content[t], p.title) for p in spec.panels]
    return _svgMontage(frame; panel_width=spec.panel_width,
                       title_height=spec.title_height, pad=spec.pad)
end

"""
    record(spec::MontageSpec, path="montage.mp4"; framerate=15, scale=1, overwrite=false) -> path

Render a movie of `spec` to `path` (extension picks the container, e.g. `.mp4`/`.gif`;
defaults to `montage.mp4` in the current directory), with every panel playing through its
frames in lockstep. Each output frame is the montage of that timepoint's frames. Errors if
`path` exists unless `overwrite=true`.

Requires the movie extension — run `using Rsvg, Cairo, FFMPEG` — otherwise a helpful
error is thrown.

# Keyword Arguments
- `framerate::Integer=15`: frames per second.
- `scale::Real=1`: rasterization scale factor; `>1` renders sharper (larger) frames.
- `overwrite::Bool=false`: allow writing over an existing `path`.

# Examples
```julia
using Montage, Rsvg, Cairo, FFMPEG
spec = montage([Panel(["a/f1.svg","a/f2.svg"]; title="A"),
                Panel(["b/f1.svg","b/f2.svg"]; title="B")])
record(spec, "compare.mp4"; framerate=15)
```
"""
function record(spec::MontageSpec, path::AbstractString="montage.mp4";
                framerate::Integer=15, scale::Real=1, overwrite::Bool=false)
    _assertWritable(path, overwrite)
    return _recordSVGMovie(spec, path, framerate, scale)
end

# Fallback (untyped args) — the movie extension adds a more-specific method, so this
# only fires when Rsvg/Cairo/FFMPEG are not loaded. No method-overwrite either way.
_recordSVGMovie(spec, path, framerate, scale) =
    error("montage movies need the movie extension — run `using Rsvg, Cairo, FFMPEG` to load it")
