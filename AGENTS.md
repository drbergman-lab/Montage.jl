# AGENTS.md — Montage.jl

Montage composes visualizations into composite figures and movies. Three verbs, declared and
exported in [`src/Montage.jl`](src/Montage.jl): `montage` (compare like-for-like across many
things), `storyboard` (one thing over time, static filmstrip), `tableau` (focal panel with
satellites, CairoMakie-only). `record` renders an animated composition. The core stitches SVG files
and has no heavy dependency; movies, `tableau` and PhysiCell support arrive through the six package
extensions in [`ext/`](ext).

Start with [`docs/src/dev/architecture.md`](docs/src/dev/architecture.md) — module map, the data
flow through one call, and the invariants. [`PRD.md`](PRD.md) is the behavioral spec,
[`progress.md`](progress.md) the session journal, and [`CLAUDE.md`](CLAUDE.md) the working
agreement for this repo (git workflow, review gates, what not to relitigate).

## Commands

Always run Julia with a project flag; never edit `Manifest.toml` or add a dependency without asking.

```bash
julia --project=. -e 'using Pkg; Pkg.test()'        # the test suite
julia --project=. test/runtests.jl                  # same suite, directly (faster to iterate)
julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'   # once
julia --project=docs docs/make.jl                   # build the docs into docs/build
julia --project=docs -e 'include("docs/journal.jl")'  # regenerate docs/src/dev/journal.md alone
```

Julia 1.13 records that `develop` path in `docs/Project.toml` under `[sources]`. Drop that section
before committing — it is absolute and machine-specific, and CI develops the package itself.

The docs environment deliberately carries every weak dependency, so a build exercises all six
extensions: a missing one is an error in `docs/make.jl`, not a quietly empty API reference. The
quick-start figures are composed during the build, so an API break fails the docs build.

## Invariants

- **The core owns every verb and type.** An extension may only *add methods* to functions the core
  already declares. Adding a function in an extension makes it unreachable without that extension.
- **The core takes no heavy dependency.** CairoMakie, PhysiCellOutput, PhysiCellModelManager, Rsvg,
  Cairo and FFMPEG are `[weakdeps]` with matching `[extensions]` entries — never `[deps]`.
- **PhysiCellOutput is the single reader path.** `MontagePhysiCellModelManagerExt` and
  `MontageCairoMakiePCMMExt` stay thin adapters: resolve a simulation id to its output folder, then
  delegate. Do not add a second PhysiCell reader.
- **Parse SVG dimensions, never hardcode them.** PhysiCell's `final.svg` happens to be 1000×1070.
- **`Panel`'s default `transform` is `identity` and must stay free** — an untransformed composition
  is byte-identical to one built with no transform support at all, and a test asserts it.
- **Titles and legends are drawn as real `<text>`**, so figures stay editable in Illustrator and
  PowerPoint. Do not nest a rendered legend image where flat elements will do.
- **A colour range is pooled across every panel and frame, and computed after filtering**, so a
  colour means the same thing everywhere in one figure.
- PCMM's source and the prototype at `~/Research/GeorgetownR01/scripts/StitchFinalSVGs.jl` are
  read-only references. All work stays inside this repository.

## Conventions

- Functions `camelCase` (`renderMovie`); internal helpers `_camelCase` (`_svgGrid`); types
  `PascalCase`; files `snake_case.jl`. The three verbs are lowercase single words by design.
- `src/montage_verb.jl` is not `montage.jl`: macOS's case-insensitive filesystem would collide it
  with `src/Montage.jl`.
- Every exported name has a docstring with arguments, return value and a runnable example. The docs
  build runs `checkdocs=:all`, so **every** docstring — internal helpers and extension methods
  included — must appear on some page, or the build fails.
- Documentation follows the tiered-docs house style: `!!! tierbrief` / `tierfull` / `tierdev` /
  `tierjournal` blocks, shallowest first, never wrapping a code block. `docs/src/dev/journal.md` is
  generated — edit the `tierjournal` blocks on the pages instead.

## Sharp edges

- The `backend` keyword and `MakieBackend` on `montage`/`storyboard` are vestigial: those verbs are
  SVG-only, and `:makie` errors on purpose. Do not implement it.
- `storyboard` rejects a frame-sequence panel. That is the design — it is the still filmstrip; use
  `montage` for a movie.
- Montage movies go through SVG frames plus FFMPEG; `tableau` movies go through `Makie.record`.
  They are different engines on purpose.
