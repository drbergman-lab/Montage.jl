```@meta
CurrentModule = Montage
```

# Montage

[`montage`](@ref) arranges a collection of homogeneous panels into a **uniform titled grid** —
the verb for comparing like-for-like across many things (e.g. the final state of every run in a
batch, side by side).

## Panels

A composition is a vector of [`Panel`](@ref)s. A panel carries its content and an optional
title:

```julia
using Montage

panels = [Panel("a/final.svg"; title="A"),
          Panel("b/final.svg"; title="B"),
          Panel("c/final.svg"; title="C")]
montage(panels)
```

For the default `:svg` backend, a panel's content is a **path to an SVG file** — each is inlined
and scaled to fit its cell (losslessly, as vector graphics). You can also pass a loose vector of
raw contents and they are wrapped as untitled panels:

```julia
montage(["a/final.svg", "b/final.svg"])   # untitled
```

## The grid

Panels are laid out row-major in a `ceil(sqrt(n))`-column grid, with uniform cells sized from the
largest panel aspect ratio so nothing clips. A title band is reserved for the whole grid only if
at least one panel is titled — an all-untitled montage wastes no vertical space. Tune the geometry
with `panel_width`, `title_height`, and `pad`.

## Output

Like every verb, `montage` **writes by default** (to `montage.svg` in the working directory) and
also returns the composed SVG string:

```julia
montage(panels)                       # writes ./montage.svg, returns the SVG string
montage(panels; output="grid.svg")    # choose the path
montage(panels; output=nothing)       # return the string, write nothing
```

Writing errors if the target exists unless you pass `overwrite=true`.

## Comparing dynamics

If a panel's content is a **vector of frame paths** (one per timepoint) instead of a single path,
`montage` becomes a *montage of movies*: every panel animates through its frames in lockstep. This
needs the movie extension — see [Movies](@ref).

```@docs
montage
Panel
```
