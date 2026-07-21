# Movie rendering for Montage — the SVG-frame + FFMPEG path.
#
# Loaded only when Rsvg, Cairo, and FFMPEG are all present. Adds the concrete
# `Montage._recordSVGMovie` method that the core `record(::MontageSpec, …)` delegates to:
# for each timepoint, rasterize the montage SVG for that frame (Rsvg + Cairo), then
# encode the PNG sequence to `path` with FFMPEG.

module MontageMovieExt

using Montage
using Rsvg, Cairo, FFMPEG

# Rasterize an SVG string to a PNG file at `png_path`, scaled by `scale`.
function _rasterizeSVG(svg::AbstractString, png_path::AbstractString, scale::Real)
    handle = Rsvg.handle_new_from_data(String(svg))
    dim = Rsvg.handle_get_dimensions(handle)
    # even dimensions keep yuv420p H.264 encoders happy
    w = 2 * ceil(Int, dim.width * scale / 2)
    h = 2 * ceil(Int, dim.height * scale / 2)
    surface = Cairo.CairoImageSurface(w, h, Cairo.FORMAT_ARGB32)
    ctx = Cairo.CairoContext(surface)
    # white backdrop (ARGB32 starts transparent; the SVG's own white rect covers most,
    # but this guards the even-dimension padding margin)
    Cairo.set_source_rgb(ctx, 1, 1, 1)
    Cairo.paint(ctx)
    Cairo.scale(ctx, w / dim.width, h / dim.height)
    Rsvg.handle_render_cairo(ctx, handle)
    Cairo.write_to_png(surface, String(png_path))
    return png_path
end

function Montage._recordSVGMovie(spec::Montage.MontageSpec, path::AbstractString,
                                 framerate::Integer, scale::Real)
    framerate > 0 || error("framerate must be positive; got $framerate")
    tmp = mktempdir()
    try
        for t in 1:spec.nframes
            svg = Montage._svgFrame(spec, t)
            _rasterizeSVG(svg, joinpath(tmp, "frame_" * lpad(t, 6, '0') * ".png"), scale)
        end
        mkpath(dirname(abspath(String(path))))
        pattern = joinpath(tmp, "frame_%06d.png")
        if lowercase(splitext(path)[2]) == ".gif"
            FFMPEG.exe("-y", "-framerate", string(framerate), "-i", pattern, String(path))
        else
            FFMPEG.exe("-y", "-framerate", string(framerate), "-i", pattern,
                       "-c:v", "libx264", "-pix_fmt", "yuv420p", String(path))
        end
    finally
        rm(tmp; recursive=true, force=true)
    end
    return path
end

end # module
