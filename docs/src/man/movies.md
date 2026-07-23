```@meta
CurrentModule = Montage
```

# Movies

Static vs. animated is an orthogonal axis: the composition verbs also produce **movies**. There is
no separate `movie=` keyword and no `_gif`/`_movie` function variants — you build a composition and
render it.

## Montage of movies

Give [`montage`](@ref) panels whose content is a **vector of frame paths** (one per timepoint) and
it renders a movie where every panel plays through its frames in lockstep — ideal for comparing
dynamics across runs. This uses the movie extension, loaded when you bring `Rsvg`, `Cairo`, and
`FFMPEG`:

```julia
using Montage, Rsvg, Cairo, FFMPEG

montage([Panel([a1, a2, a3]; title="A"),      # a1,a2,a3 are per-timepoint SVG paths
         Panel([b1, b2, b3]; title="B")];
        output = "compare.mp4", framerate = 15)
```

Under the hood the two-step is available too: with `output=nothing`, an animated `montage` returns
a [`MontageSpec`](@ref) that [`record`](@ref) animates.

```julia
spec = montage(animated_panels; output=nothing)   # a MontageSpec
record(spec, "compare.mp4"; framerate=15)
```

Frames are aligned by index and truncated to the shortest sequence (time-based alignment is a
planned enhancement).

Rendering rasterizes each timepoint's composed SVG (via `Rsvg`/`Cairo`) and encodes the sequence
with `FFMPEG`, preserving the exact styling of the source SVGs.

## Tableau movies

A [`tableau`](@ref) can be animated over time — the whole data-driven scene evolving frame by
frame via `Makie.record` (CairoMakie). This is driven by a data-source method; for PhysiCell
simulations it is `index=:all` (or a range of snapshots) on the simulation method — see
[Extensions & PhysiCell](@ref).

```@docs
record
MontageSpec
```
