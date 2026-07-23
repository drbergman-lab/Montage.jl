```@meta
CurrentModule = Montage
```

# Storyboard

[`storyboard`](@ref) stitches an **ordered** sequence of frames into a single static figure — the
verb for showing one subject evolving over time (a filmstrip for a poster or paper). Where
[`montage`](@ref) is an unordered grid, `storyboard` reads in time order and defaults to a
**single row**.

```julia
using Montage

storyboard([Panel("t0.svg"; title="t = 0"),
            Panel("t1.svg"; title="t = 120"),
            Panel("t2.svg"; title="t = 240"),
            Panel("t3.svg"; title="t = 360")])
```

Titles are exposed precisely so you can label each frame with its timestamp. Set `ncols` to wrap a
long strip into a grid while preserving time order:

```julia
storyboard(frames; ncols=4)   # wrap into rows of four
```

Storyboard is deliberately **static** — a frame sequence panel is rejected. For a single-subject
*movie*, animate its frames with [`montage`](@ref) instead (see [Movies](@ref)). Output behaves
exactly as for `montage` (writes `storyboard.svg` by default; `output=nothing` returns the string;
`overwrite` guards existing files).

```@docs
storyboard
```
