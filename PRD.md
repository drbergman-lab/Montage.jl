# Product Requirements Document — Montage.jl

> **Purpose:** This document defines the complete feature set of Montage in behavioral terms. It is the authoritative answer to "what should this system do?" Read this at the start of any feature session to establish alignment between intent and implementation plan.

---

## Product Overview

**Vision:** Montage turns PhysiCell visualizations into intentionally-structured composite figures and movies. It gives modelers a small, memorable vocabulary — three verbs — for the three distinct things they actually want to say with a composite image, and treats animation as an orthogonal capability layered on all three.

**Target Users:** Computational modelers running PhysiCell simulations (typically via PhysiCellModelManager.jl) who need publication- and presentation-ready composite figures and movies.

**Status:** **Planned — not yet implemented.** `src/Montage.jl` is a stub. This document records the intended behavior and the decisions still open with the user; it will be trimmed to match reality as features land.

**Design principles:**
1. Three verbs; time is a separate `record(spec, path)` entry point, not a combinatorial explosion of `verb × static/movie` function names.
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
- `montage(panels; backend=:svg, panel_width=300, title_height=34, pad=12, output=nothing)`.
- `panels` is a `Vector{Panel}` or a loose vector of raw contents (each auto-wrapped as an untitled `Panel`).
- Grid geometry: `ncols = ceil(sqrt(n))`, row-major; uniform cells sized from the **max aspect ratio** across panels so nothing overflows or clips; children centered via `preserveAspectRatio`.
- A centered bold title is drawn per titled panel. The title band is reserved for the whole grid **only if at least one panel is titled** — an all-untitled composition reserves no band (no wasted white space).
- Returns the composed SVG `String`; writes it to `output` if a path is given.
- `backend=:makie` errors with a message to `using CairoMakie` until that extension is built.

**SVG fast-path (regression target — the prototype):**
- Inline each PhysiCell `.svg` as a nested, positioned `<svg>` element: strip its XML declaration and root `<svg …>` opening tag, then re-wrap with a new opening tag carrying `x`, `y`, `width`, `height`, `viewBox="0 0 <iw> <ih>"`, and `preserveAspectRatio="xMidYMid meet"`. The `viewBox` is what makes the child scale instead of clip — this is the crux.
- Intrinsic dims parsed by regex from the child root tag (`width`/`height`); **parse, never hardcode** (PhysiCell SVGs happen to be 1000×1070).
- Defaults from the prototype: `panel_width=300`, `title_height=34`, `pad=12`; titles bold Arial 22.

**Acceptance criteria:**
- Regression vs. prototype: `montage(Simulation)` (extension) produces a ~6-col grid of 34 titled "Sim N" panels, scaled cleanly, no clipping — visually matching the prototype output.
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

**One-line description:** Render any verb as an animation over a time dimension via `Makie.record`.

**Priority:** Must-have (headline feature).

**Behavioral specification:**
- `storyboard` movie = single-simulation time movie.
- `montage` movie = every sim panel animates through time **simultaneously** → compare dynamics across sims.
- `tableau` movie = the whole composed scene animates through time together.
- **API:** a verb builds a composition spec; `record(spec, path; framerate=…)` animates it (driving `Makie.record`). Lives in the CairoMakie extension. No per-verb `movie=` kwarg or `_movie`/`_gif` variants.

**Acceptance criteria:**
- A short movie renders for each verb and plays with all frames present at the requested framerate.

---

## Feature: PCMM Extension

**One-line description:** Add convenience methods that resolve PhysiCell simulation ids to files/data, loaded only when PCMM is present.

**Priority:** Must-have (this is how the tool is actually used in practice).

**Behavioral specification:**
- Ships as `ext/MontagePhysiCellModelManagerExt.jl`, wired via `[weakdeps]` + `[extensions]` in `Project.toml`.
- Adds methods on PCMM types to the core verbs, e.g.:
  - `montage(::Type{Simulation}, sim_ids=simulationIDs(); …)`
  - `storyboard(::Type{Simulation}, sim_id; …)`
  - `tableau(::Type{Simulation}, sim_id; time=:final, substrates=…, …)`
- File/data resolution uses PCMM primitives: `trialFolder(Simulation, id)/output/` holds `final.svg`, `initial.svg`, `legend.svg`, and `snapshot00000000.svg …` (the SVG-path frame source); `PhysiCellSnapshot`/`PhysiCellSequence` + `substrates`/`cells` DataFrames + `substrateNames`/`cell_type_to_name_dict` are the data-path source.
- Core owns the generic verbs; the extension only **adds methods** (cannot define new exported functions).

**Acceptance criteria:**
- With PCMM loaded, the `::Type{Simulation}` methods work end-to-end on the dev project.
- With PCMM absent, the core loads and the generic verbs work; the extension methods are simply unavailable.

---

## Decisions (resolved 2026-07-21)

1. **Backend strategy:** SVG string-stitching is the **core default** (`backend=:svg`), with no heavy deps. CairoMakie lives behind an extension (`MontageCairoMakieExt`); `backend=:makie` requires `using CairoMakie` and errors helpfully otherwise. Backend is a **kwarg**, keeping the API surface slim.
2. **Movie API surface:** a separate **`record(spec, path; framerate=…)`** entry point (in the CairoMakie extension) that animates a composition spec. No per-verb `movie=` kwarg, no `_movie`/`_gif` variants.
3. **Core input contract:** a typed **`Panel`/`Layout` spec** (not bare tuples). A `Panel` carries its title and content (an image path for the SVG path, or a plotting callback + data for the Makie path).
4. **v1 scope:** land **`montage` first** — port the SVG-path prototype and regression-test it against the known-good 34-sim grid — then add `storyboard`, `tableau`, and movies incrementally.

### Still open (decide when the relevant feature is built)

- **`tableau` layout spec:** how to declare focal vs. satellite panels and where each substrate heatmap goes (auto-ring around center? explicit positions?). Decide when building `tableau`.
- **Default output location** and the non-overwrite naming scheme (keep the prototype's ` copy (n).svg` scheme, or switch to explicit-only / timestamp). Decide when building `montage`.
