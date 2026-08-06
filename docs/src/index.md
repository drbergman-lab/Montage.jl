```@meta
CurrentModule = Montage
```

# Montage.jl

Montage composes visualizations into intentionally-structured composite figures — and movies.
It gives you three verbs for the three distinct things a composite figure can say, and treats
*static vs. animated* as an orthogonal choice.

| Verb | Use it to… | Looks like |
|------|-----------|-----------|
| [`montage`](@ref) | **compare** like-for-like across many things | uniform grid of equal panels |
| [`storyboard`](@ref) | show **one thing evolving over time** | ordered filmstrip |
| [`tableau`](@ref) | show how **heterogeneous parts of one state relate** spatially | focal panel + satellites |

## Design in one breath

- **A light core.** The default backend stitches SVG files into a composite — no heavy
  dependencies. `montage` and `storyboard` work out of the box.
- **Extensions add power, not weight.** Movies (via [`record`](@ref)) and `tableau` (via
  CairoMakie) live in package extensions, loaded only when you bring their dependencies.
- **Typed panels.** Compositions are built from [`Panel`](@ref)s, so the intentional structure
  is explicit rather than implied by tuple positions.

## Installation

```julia-repl
pkg> registry add https://github.com/drbergman-lab/BergmanLabRegistry
pkg> add Montage
```

Montage is registered in the [BergmanLabRegistry](https://github.com/drbergman-lab/BergmanLabRegistry),
alongside [PhysiCellModelManager.jl](https://github.com/drbergman-lab/PhysiCellModelManager.jl) and
[PhysiCellOutput.jl](https://github.com/drbergman-lab/PhysiCellOutput.jl), so the registry only
needs adding once.

## Quick start

```julia
using Montage

# Compare things side by side — writes ./montage.svg, and returns the SVG string
montage([Panel("a/final.svg"; title="A"), Panel("b/final.svg"; title="B")])

# One thing over time, as an ordered strip — writes ./storyboard.svg
storyboard([Panel("t0.svg"; title="t = 0"),
            Panel("t1.svg"; title="t = 120"),
            Panel("t2.svg"; title="t = 240")])
```

Every verb writes its output by default and also returns it; pass `output=nothing` to get the
result back without writing, or `output="path"` to choose where it goes. Movies and `tableau`
need their extensions — see [Movies](@ref) and [Tableau](@ref).

## Manual

```@contents
Pages = [
    "man/montage.md",
    "man/storyboard.md",
    "man/tableau.md",
    "man/movies.md",
    "man/extensions.md",
    "reference.md",
]
Depth = 1
```

## PhysiCell simulations

Montage grew up in the [PhysiCell](https://physicell.org) ecosystem. Convenience methods that
build compositions straight from simulation output are provided through an extension today, and
are planned to move to a dedicated `PhysiCellMontage.jl` package — see
[Extensions & PhysiCell](@ref).
