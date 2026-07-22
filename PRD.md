# Product Requirements Document — Montage.jl

> **Purpose:** This document defines the complete feature set of Montage in behavioral terms. It is the authoritative answer to "what should this system do?" Read this at the start of any feature session to establish alignment between intent and implementation plan.

---

## Product Overview

**Vision:** Montage turns PhysiCell visualizations into intentionally-structured composite figures and movies. It gives modelers a small, memorable vocabulary — three verbs — for the three distinct things they actually want to say with a composite image, and treats animation as an orthogonal capability layered on all three.

**Target Users:** Computational modelers running PhysiCell simulations (typically via PhysiCellModelManager.jl) who need publication- and presentation-ready composite figures and movies.

**Status:** **Planned — not yet implemented.** `src/Montage.jl` is a stub. This document records the intended behavior and the decisions still open with the user; it will be trimmed to match reality as features land.

**Design principles:**
1. Three verbs; whether a verb renders a still image or a movie is decided by its panel content (single image vs. frame sequence), not by a combinatorial explosion of `verb × static/movie` function names. `record` is the underlying movie renderer.
2. A **light core** with no heavy dependencies. The SVG string-stitch backend is the built-in default. Both CairoMakie and PCMM are optional, reached only through package extensions — users who only want static SVG montages never load either.
3. Panels are a typed `Panel`/`Layout` spec, so the "intentional structure" is explicit in the API rather than implied by tuple positions.

---

## The Three Composition Verbs

| Verb | Intent | Layout | Canonical use |
|------|--------|--------|---------------|
| `montage` | Compare like-for-like across many things | Uniform grid of equal panels | Final states across N simulations, side by side |
| `storyboard` | Show one thing evolving over time | 1-D ordered sequence of frames | Time evolution of a single simulation |
| `tableau` | Show how heterogeneous components of one state relate spatially | Focal panel + satellite panels | Multi-channel view of one simulation at one time |

`montage` and `storyboard` are both uniform grids of homogeneous panels; they differ only in what a panel means and the reading order (unordered scan vs. temporal sequence). `tableau` is a single deliberately-composed scene with a focal element and related elements arranged around it — not a uniform grid; it needs a real layout engine (Makie `GridLayout` / insets), a shared spatial axis, and colorbars.

---

## Feature: `montage` (core) — **implemented (SVG backend), 2026-07-21**

**One-line description:** Arrange a collection of homogeneous panels into a uniform titled grid.

**Priority:** Must-have (first to land; port + regression against the prototype).

**Behavioral specification:**
- `montage(panels; backend=:svg, panel_width=300, title_height=34, pad=12, output=<auto>, overwrite=false, framerate=15)`.
- `panels` is a `Vector{Panel}` or a loose vector of raw contents (each auto-wrapped as an untitled `Panel`). Panel content is a single SVG path (still) or a `Vector` of paths (movie frames) — see the Movies feature.
- Grid geometry: `ncols = ceil(sqrt(n))`, row-major; uniform cells sized from the **max aspect ratio** across panels so nothing overflows or clips; children centered via `preserveAspectRatio`.
- A centered bold title is drawn per titled panel. The title band is reserved for the whole grid **only if at least one panel is titled** — an all-untitled composition reserves no band (no wasted white space).
- **Writes by default** — `output` defaults to `montage.svg` (still) / `montage.mp4` (movie) in the current directory, erroring if it exists unless `overwrite=true`. Returns the SVG `String` (still) or output path (movie); `output=nothing` returns the in-memory result (SVG `String` or `MontageSpec`) without writing.
- `backend=:makie` errors with a message to `using CairoMakie` until that extension is built.

**SVG fast-path (regression target — the prototype):**
- Inline each PhysiCell `.svg` as a nested, positioned `<svg>` element: strip its XML declaration and root `<svg …>` opening tag, then re-wrap with a new opening tag carrying `x`, `y`, `width`, `height`, `viewBox="0 0 <iw> <ih>"`, and `preserveAspectRatio="xMidYMid meet"`. The `viewBox` is what makes the child scale instead of clip — this is the crux.
- Intrinsic dims parsed by regex from the child root tag (`width`/`height`); **parse, never hardcode** (PhysiCell SVGs happen to be 1000×1070).
- Defaults from the prototype: `panel_width=300`, `title_height=34`, `pad=12`; titles bold Arial 22.

**Acceptance criteria:**
- Regression vs. prototype: `montage(Simulation, simulationIDs())` (extension) produces a ~6-col grid of titled "Sim N" panels, scaled cleanly, no clipping — visually matching the prototype output.
- Core works with no PCMM present, given hand-written panels.

---

## Feature: `storyboard` (core)

**One-line description:** Arrange an ordered time sequence of frames from one subject.

**Priority:** Must-have (v1 or fast-follow — see open decision 6).

**Behavioral specification:**
- Panels are an **ordered** sequence (frames of one simulation over time); reading order is temporal.
- Static output = frames laid out in a grid (a `montage`-like uniform grid, but ordered).
- Movie output = play the frames in order → a single-simulation movie.

**Acceptance criteria:**
- `storyboard(Simulation, sim_id; movie="out.mp4", framerate=15)` produces an mp4 that plays with all frames in time order.

---

## Feature: `tableau` (core)

**One-line description:** Compose a single scene with a focal panel and satellite panels arranged around it.

**Priority:** Must-have (forces the CairoMakie path).

**Behavioral specification:**
- One focal panel (e.g. cell scatter) centered; satellite panels (e.g. one substrate heatmap + colorbar per channel) arranged around it, sharing a spatial extent with the focal panel.
- Built with Makie `GridLayout` / insets; real `Colorbar`s; shared axes.
- Requires re-plotting from data (not SVG rasterization) → PCMM data layer via the extension for the PCMM convenience methods.
- Exact layout-declaration API (auto-ring around center vs. explicit positions) is an **open decision**.

**Acceptance criteria:**
- `tableau(Simulation, sim_id; time=:final, substrates=…)` renders the cell scatter centered with one heatmap+colorbar per substrate around it, all on a shared spatial extent.

---

## Feature: Movies (orthogonal time axis)

**One-line description:** Render a composition as an animation over a time dimension.

**Priority:** Must-have (headline feature).

**Behavioral specification:**
- `montage` movie = every sim panel animates through time **simultaneously** → compare dynamics across sims. **(In progress — the first movie feature.)**
- `storyboard` movie = single-simulation time movie. *(later)*
- `tableau` movie = the whole composed scene animates through time together. *(later, CairoMakie path)*
- **API:** the **panel content decides still vs. movie** — if any panel's content is a frame sequence, `montage` renders a movie **in one call** (writing `.mp4`), auto-picking the output extension. `output=nothing` returns a [`MontageSpec`](@ref) instead, which `record(spec, path; framerate, scale, overwrite)` animates (the underlying renderer + an escape hatch for finer control). No per-verb `movie=` kwarg or `_movie`/`_gif` variants.
- **Two rendering paths:**
  - **SVG-frame path (default, Option A):** for each timepoint, compose the montage SVG of that timepoint's frames via the core `_svgMontage`, rasterize (Rsvg + Cairo), and encode the PNG sequence with FFMPEG. Preserves exact PhysiCell styling; reuses the SVG backend; no CairoMakie. Lives in `ext/MontageMovieExt.jl` (weakdeps `Rsvg`, `Cairo`, `FFMPEG`). **This is the path used for the montage-of-movies feature.**
  - **CairoMakie path (later):** `Makie.record` for `tableau` and true data-driven/heatmap movies.
- **`MontageSpec`** (core type): a grid of frame-sequence panels + a common frame count + layout params. `montage` builds it internally (and returns it when `output=nothing`); `_svgFrame(spec, t)` renders one timepoint's montage SVG.
- **Frame alignment across sims:** by **frame index**, truncated to the shortest sequence, with a warning when lengths differ. Time-based alignment (nearest snapshot on a common time grid) is a **planned follow-up** — see the to-do in progress.md.

**Acceptance criteria:**
- `record(montage(frame_panels), "out.mp4")` writes a playable video with `nframes` frames at the requested framerate, each frame the montage of that timepoint.
- Calling `record` without the movie extension loaded errors with a message to `using Rsvg, Cairo, FFMPEG`.

---

## Feature: PCMM Extension

**One-line description:** Add convenience methods that resolve PhysiCell simulation ids to files, loaded only when PCMM is present.

**Priority:** Must-have (this is how the tool is actually used in practice).

**Status:** `montage(::Type{Simulation}, …)` **implemented (2026-07-21)**. `storyboard`/`tableau` methods pending those verbs.

**Behavioral specification:**
- Ships as `ext/MontagePhysiCellModelManagerExt.jl`, wired via `[weakdeps]` + `[extensions]` in `Project.toml`. Triggered by **PhysiCellModelManager** (the added knowledge is the PhysiCell output-file convention), though `Simulation`/`simulationIDs`/`trialFolder`/`dataDir` are ModelManager's, re-exported by PCMM.
- `montage(::Type{Simulation}, sim_ids; index=:final, title=(id->"Sim $id"), panel_width=300, title_height=34, pad=12, output::Union{Nothing,AbstractString}=<auto>, overwrite=false, framerate=15)`. `sim_ids` is required — `simulationIDs()` covers "all sims" explicitly; there is no all-sims default. The **`index` value decides still image vs. movie** (one opinionated call that produces output; no separate `frames` kwarg).
  - **Still image** (`index` is `:final`/`:initial`, or an Integer): one panel per sim selected the same way as PCMM's `PhysiCellSnapshot` — a Symbol names the state SVG, an Integer selects that indexed snapshot (`snapshotNNNNNNNN.svg`). Missing files skipped with a warning. Writes an SVG.
  - **Movie** (`index` is `:all` or a vector/range of snapshot indices): each panel plays that sim's snapshot sequence (index-aligned, truncated to shortest); rendered via `record` (requires the movie extension).
  - **Output:** `output` defaults to `dataDir()/outputs/montage.svg` (still) or `…/montage.mp4` (movie), erroring if it exists unless `overwrite=true`. For a still image, `output=nothing` returns the SVG string instead of writing; a movie always needs a path (`nothing` errors). `framerate` applies to movies.
- File resolution uses `trialFolder(Simulation, id)/output/` (`final.svg`, `initial.svg`, `snapshot00000000.svg …`). Data-driven primitives (`PhysiCellSnapshot`/`PhysiCellSequence` + `substrates`/`cells` DataFrames) are reserved for the future `tableau`/data-movie path.
- Core owns the generic verbs; the extension only **adds methods**.

**Acceptance criteria:**
- With PCMM loaded, `montage(Simulation, simulationIDs())` (still) and `montage(Simulation, ids; index=:all, output="x.mp4")` (movie) work end-to-end on the dev project. ✓ verified (static grid + 4-sim movie).
- With PCMM absent, the core loads and the generic verbs work; the extension methods are simply unavailable. ✓

---

## Decisions (resolved 2026-07-21)

1. **Backend strategy:** SVG string-stitching is the **core default** (`backend=:svg`), with no heavy deps. CairoMakie lives behind an extension (`MontageCairoMakieExt`); `backend=:makie` requires `using CairoMakie` and errors helpfully otherwise. Backend is a **kwarg**, keeping the API surface slim.
2. **Movie API surface:** `montage` renders a movie **in one call** when its panels carry frame sequences (auto-writing `.mp4`); `output=nothing` yields a `MontageSpec` that the underlying **`record(spec, path; framerate, scale, overwrite)`** animates. No per-verb `movie=` kwarg, no `_movie`/`_gif` variants. Rendering uses the **SVG-frame + FFMPEG path** (Option A, resolved 2026-07-21) in `ext/MontageMovieExt.jl`; CairoMakie is reserved for later `tableau`/data-driven movies.
3. **Core input contract:** a typed **`Panel`/`Layout` spec** (not bare tuples). A `Panel` carries its title and content (an image path for the SVG path, or a plotting callback + data for the Makie path).
4. **v1 scope:** land **`montage` first** — port the SVG-path prototype and regression-test it against the known-good 34-sim grid — then add `storyboard`, `tableau`, and movies incrementally.

### Still open (decide when the relevant feature is built)

- **`tableau` layout spec:** how to declare focal vs. satellite panels and where each substrate heatmap goes (auto-ring around center? explicit positions?). Decide when building `tableau`.
- **Default output location** and the non-overwrite naming scheme (keep the prototype's ` copy (n).svg` scheme, or switch to explicit-only / timestamp). Decide when building `montage`.
- **Time-based frame alignment (follow-up to montage-movies):** v1 aligns frames by index and truncates to the shortest sequence. Add an option to align by *simulation time* — build a common time grid and select each sim's nearest snapshot, holding the last frame for sims that ended earlier — so sims with different cadences/durations compare correctly.
