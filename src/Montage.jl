module Montage

# Core types (Panel, Layout, backend selectors) — owned here so extensions can add methods.
include("types.jl")

# SVG string-stitch backend — the core default, no heavy dependencies.
include("svg_backend.jl")

# Composition verbs. Note: the montage verb lives in `montage_verb.jl`, not `montage.jl`,
# because macOS's case-insensitive filesystem would collide `montage.jl` with `Montage.jl`.
include("montage_verb.jl")

# Movies: MontageSpec builder, per-frame SVG, and the `record` entry point.
# The renderer (rasterize + encode) is added by ext/MontageMovieExt.jl.
include("movie.jl")

# storyboard: one subject's time evolution as a static ordered strip.
include("storyboard.jl")

# tableau: focal + satellite scene (CairoMakie extensions implement it).
include("tableau.jl")

export Panel, MontageSpec, montage, storyboard, tableau, record

end
