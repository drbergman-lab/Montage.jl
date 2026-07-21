# progress.md — Montage.jl Session Journal

> **Purpose:** Session-level decisions, rejected approaches, and open questions.
> Unlike [PRD.md](PRD.md) (specification) and [README.md](README.md) (completion status), this file captures the *reasoning* behind decisions — things that would otherwise exist only in ended chat history.

---

## Session: Initialization — docs scaffold + design intake (2026-07-21)

### Goal
Stand up the support docs (CLAUDE.md, PRD.md, progress.md, README Implementation Status) for a fresh `Montage.jl` package, distilling the design brief in `HANDOFF.md` into the living documents used by future sessions. No package code yet.

### Where the design came from
`HANDOFF.md` (uncommitted, repo root) is the seed brief from a prior conversation. It captured a working prototype (`StitchFinalSVGs.jl`) plus a design discussion that produced the three-verb vocabulary and the backend architecture question. These docs are the living successors to that brief.

### Key decisions carried in as fixed (not to relitigate)
- **Name `Montage.jl` / module `Montage`**, with an eponymous `montage` verb.
- **Core must not depend on PCMM.** PCMM support is a package extension (weakdep). Rationale: keep the composition engine simulator-agnostic and installable without the heavy PCMM stack; extensions can only add methods to functions the core already owns, so the verbs are declared/exported in the core.
- **Movies are first-class via CairoMakie** (`Makie.record`). This is what tips the architecture toward Makie as the primary backend.

### The three-verb vocabulary (the crux of the naming discussion)
"One grid mechanism" wasn't enough — there are three distinct *intents*:
- `montage` and `storyboard` are both uniform grids of homogeneous panels; they differ only in panel meaning + reading order (unordered scan vs. temporal sequence). The ImageJ/Fiji "Make Montage" precedent covers both — hence the package name.
- `tableau` is the "true tableau": one deliberately-composed scene, focal + satellites. Not a uniform grid — needs a real layout engine, shared spatial axis, colorbars. This is why `tableau` forces the CairoMakie path.

Time (static vs. movie) is treated as an **orthogonal axis**, not a fourth verb — to avoid a `montage`/`montage_movie`/`montage_gif` combinatorial mess.

### Backend architecture — the biggest open question
Two ways to build a composite:
- **(A) SVG string-stitching** (the prototype): inline existing PhysiCell `.svg` as nested `<svg>`. Pros: lossless vector, exact PhysiCell styling, no re-rendering, no data access. Cons: static only, no real heatmaps/colorbars, can't compose visuals that don't already exist as SVGs.
- **(B) CairoMakie**: `Figure`+`GridLayout`, `heatmap!`/`scatter!`, `Colorbar`, `Makie.record`. Pros: required for movies; `GridLayout` naturally expresses the tableau; real colorbars/shared axes; one engine for all three verbs × static/movie. Cons: heavier dep; getting *existing* SVGs into Makie means rasterizing (loses vector crispness) or re-plotting from data (more work).

**Leaning:** CairoMakie primary/unifying, SVG-stitch kept as an optional static fast-path for the narrow "stitch existing SVGs into a vector-perfect static montage" case. Flagged as an open decision for the user, but movies + data-driven tableau both point this way.

### Prototype — algorithm source of truth (SVG path)
`/Users/dbergman1/Research/GeorgetownR01/scripts/StitchFinalSVGs.jl`. Must-preserve, non-obvious bits:
- **Nested-SVG scaling trick:** re-wrap each child with a new `<svg>` opening tag carrying `viewBox="0 0 <iw> <ih>"` + `preserveAspectRatio="xMidYMid meet"`. The `viewBox` is what makes it scale instead of clip.
- Parse intrinsic dims from the child root tag by regex — **don't hardcode** the 1000×1070.
- Grid: `ncols = ceil(sqrt(n))`, uniform cells from the **max aspect ratio**.
- Defaults `panel_width=300`, `title_height=34`, `pad=12`; bold Arial 22 titles.
- Non-overwrite output naming (` copy (n).svg`) — keep or replace (open decision 5).

### PCMM data access (for the data-driven / extension path)
PCMM uses Plots.jl + RecipesBase, **not** Makie — don't reuse its recipes; Montage brings its own CairoMakie stack. Data primitives (in PCMM `src/loader.jl`): `PhysiCellSnapshot(sim_id, index)` (fields `time`, `cells`, `substrates`, `mesh`, graphs), `PhysiCellSequence(sim_id; …)`, `substrates` DataFrame (`[:x,:y,:z,:volume,<name…>]`, one row/voxel → reshape for `heatmap!`), `substrateNames(seq)`, `cells` DataFrame + `cell_type_to_name_dict`, `loadSubstrates!(snapshot)`, snapshot `index` may be `Int` or `Symbol` (`:final`/`:initial`). File resolution: `trialFolder(Simulation,id)/output/` holds `final.svg`/`initial.svg`/`legend.svg`/`snapshotNNNNNNNN.svg`; `simulationIDs()` lists all sims.

### Decisions resolved (with the user, same session)
The user's answers refined the HANDOFF architecture in one important way — **CairoMakie is demoted from "primary core engine" to an optional extension**, matching PCMM. The core stays light; SVG stitching is the built-in default. Specifically:
1. **Backend:** SVG string-stitch is the core default (`backend=:svg`, no heavy deps). CairoMakie lives behind `MontageCairoMakieExt`; `backend=:makie` requires `using CairoMakie` and errors helpfully if absent. Backend selection is a **kwarg** (slim API surface) — the user's explicit preference. This supersedes HANDOFF's "CairoMakie primary, SVG as fast-path": here SVG is the *default* and Makie is the *opt-in*.
2. **Movie API:** a separate **`record(spec, path; framerate=…)`** (in the CairoMakie ext), not a per-verb `movie=` kwarg.
3. **Input contract:** typed **`Panel`/`Layout` structs**, not bare tuples.
4. **v1 scope:** **`montage` first** (SVG-path port + regression vs. the 34-sim grid), then `storyboard`/`tableau`/movies.

Consequence: there are (at least) **two extensions** — `MontageCairoMakieExt` (Makie backend + `tableau` + `record`) and `MontagePhysiCellModelManagerExt` (`::Type{Simulation}` convenience). `tableau`-from-PCMM-data needs both loaded. `Project.toml`: CairoMakie/Rsvg/Cairo and PCMM all go in `[weakdeps]`, not `[deps]`.

Still deferred until their feature is built: the `tableau` layout spec, and the default output location + non-overwrite naming scheme.

### Status
Design brief approved same session; implemented on branch `feature/montage-svg`. See next entry.

---

## Session: `montage` v1 — SVG backend (2026-07-21)

### What was built
Branch `feature/montage-svg`. The first working verb, SVG backend only.
- `src/types.jl` — `Panel(content; title="")`, backend selector types (`MontageBackend`, `SVGBackend`, `MakieBackend`), `montageBackend(::Symbol)`, and `_asPanels` (loose-input normalization: a bare vector of contents becomes untitled `Panel`s).
- `src/svg_backend.jl` — `_svgDimensions`, `_nestedSVG` (the `viewBox` scaling trick), `_svgMontage` (grid builder), `_escapeXML`. Ported from the prototype.
- `src/montage_verb.jl` — the `montage` verb; dispatches on backend type. `:svg` in core; `:makie` is a core fallback that errors until `MontageCairoMakieExt` exists.
- `src/Montage.jl` — includes + `export Panel, montage`.
- `test/runtests.jl` — 26 tests on hand-written tiny SVGs; no PCMM, no CairoMakie.

### Design decisions
- **Return the SVG string; `output` is opt-in.** The core is location-agnostic (no data-dir assumption), so `montage(panels)` returns the composed SVG and only writes when `output=` is given. The PCMM extension will supply the `data/outputs/...` default path and the prototype's non-overwrite ` copy (n).svg` naming — deferring open decision #5 to where it actually matters.
- **Title band reserved per-grid, not per-panel.** `montage` is a *uniform* grid, so the band height is `title_height` if any panel is titled, else `0`. Keeps geometry uniform while honoring the user's "no wasted white space when untitled" preference. Mixed titled/untitled still reserves the band uniformly (documented).
- **XML-escape titles** (`_escapeXML`) so user titles can't break the SVG.

### Gotcha — macOS case-insensitive filesystem
The verb file **cannot** be named `montage.jl`: on the default macOS filesystem it collides with the module file `Montage.jl` (same inode), silently overwriting it. Named it `montage_verb.jl` instead; future verbs will follow (`storyboard_verb.jl`, `tableau_verb.jl`) for symmetry, or the collision only actually bites `montage`. Documented in a comment in `Montage.jl`.

### Verification
- `Pkg.test()` green, 26/26, precompiles with no method-overwrite warnings (the two-inner-constructor `Panel` first written collided on `Panel(::Any)`; fixed by making the coercing positional an *outer* constructor).
- **Regression vs. prototype:** ran core `montage` on the dev project's 40 sims (`data/outputs/simulations/*/output/final.svg`) with `Sim N` titles → 7-col grid, scaled cleanly, no clipping, matching the prototype's known-good look. Output rendered via `rsvg-convert` and eyeballed (1400×1412 px).

### Open / next
- Not committed yet (awaiting user approval).
- `Project.toml` still has no `[weakdeps]`/`[extensions]` — added with the CairoMakie/PCMM slices.
- Next verb likely `storyboard` (SVG static path first), then the CairoMakie extension for movies + `tableau`.
