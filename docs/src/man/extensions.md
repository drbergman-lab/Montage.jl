```@meta
CurrentModule = Montage
```

# Extensions & PhysiCell

Montage keeps a **light core**: the SVG-stitch backend behind `montage` and `storyboard` has no
heavy dependencies. Everything that needs a big stack lives in a
[package extension](https://docs.julialang.org/en/v1/manual/code-loading/#man-extensions), loaded
automatically only when you bring the relevant packages. Requesting a feature without its extension
loaded produces a clear error telling you what to `using`.

| Extension | Load by | Unlocks |
|-----------|---------|---------|
| `MontageMovieExt` | `using Rsvg, Cairo, FFMPEG` | rendering montage-of-movies with [`record`](@ref) |
| `MontageCairoMakieExt` | `using CairoMakie` | [`tableau`](@ref) and its data-driven layout engine |

Because the core owns the verb functions, extensions only *add methods* to them — so the same
`montage`/`tableau` you already call simply gains new capabilities when a dependency is present.

## PhysiCell simulations

Montage originated in the [PhysiCell](https://physicell.org) ecosystem, and provides convenience
methods that build compositions straight from simulation output — e.g. a grid of final states, a
snapshot filmstrip, or a cell/substrate tableau (and its movie) for a single simulation.

Today these are delivered through extensions keyed on
[PhysiCellModelManager.jl](https://github.com/drbergman-lab/PhysiCellModelManager.jl) (PCMM),
which resolve a simulation to its output folder and read its data.

!!! note "Planned change"
    This PhysiCell integration is slated to move into a dedicated **`PhysiCellMontage.jl`** package.
    That package will also support PhysiCell users who don't use PCMM — driving the verbs from an
    **output-folder path** rather than a simulation id — while Montage.jl itself stays PhysiCell-free.
    Because it relocates the `montage(::Type{Simulation}, …)` methods off of Montage, it is a
    breaking change and is being settled before Montage's first registration.
