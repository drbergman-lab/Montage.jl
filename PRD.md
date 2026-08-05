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

## Feature: `storyboard` (core) — **implemented (SVG backend), 2026-07-22**

**One-line description:** Arrange an ordered time sequence of frames from one subject into a static filmstrip.

**Priority:** Must-have.

**Scope decision:** `storyboard` is **static only** — a filmstrip for a poster/paper. Movies are `montage`'s and (later) `tableau`'s job, so storyboard deliberately has no movie path.

**Behavioral specification (core):**
- `storyboard(panels; backend=:svg, ncols=length(panels), panel_width=300, title_height=34, pad=12, output="storyboard.svg", overwrite=false)`.
- Panels are an **ordered** sequence; laid out row-major, defaulting to a **single row** (`ncols = n`). `ncols` wraps into a grid while preserving time order.
- Each panel's title is exposed (where timestamps go). Frame-sequence (animated) panels are rejected — storyboard is static.
- Shares the `_svgGrid(panels; ncols, …)` builder with `montage`. Writes by default (`storyboard.svg`), `output=nothing` returns the string, same overwrite guard.

**PCMM extension** (`storyboard(::Type{Simulation}, sim_id; …)`): operates on **one** simulation. Timepoints via `index` (a vector of `Integer` snapshot indices and/or `:initial`/`:final`) **or** `n_snapshots` (default 4: evenly-spaced spanning the run, including endpoints). `n_snapshots` defaults to `length(index)` when `index` is given; passing both with different lengths errors. Frame titles are the snapshots' simulation times via a `title` function (default `t -> "t = $t"`). Writes under `dataDir()/outputs/storyboard.svg` by default.

**Acceptance criteria:**
- `storyboard(Simulation, sim_id)` writes a single-row filmstrip of 4 evenly-spaced, timestamp-titled frames. ✓ verified on the dev project.
- Core works with no PCMM, given hand-written ordered panels.

---

## Feature: Cell-type legend for `montage` / `storyboard` — **implemented 2026-08-05**

**One-line description:** Draw a cell-type legend alongside a stitched-SVG composition, built from the cell types the composition actually shows.

**Priority:** Should-have (a montage of colored cells is unreadable without a key).

**Where the entries come from:** PhysiCell's own `output/legend.svg`, which already carries exactly the data a legend needs — one row per **configured** cell type, giving both the name and the colour PhysiCell draws it with. It is parsed for `(label, colour)` pairs; the legend is then **drawn** by Montage rather than nested, so it is compact, wraps, matches the title font, and stays editable.

Two consequences worth stating:
- Cost is one ~1.5 KB file **per simulation**, not per frame — it does not matter how many snapshots a movie has (64 sims: 13.9 ms, 97 KB).
- The legend describes what the model **can** contain per the config, deliberately *not* narrowed to what is visible in a given snapshot. That is also what makes one fixed legend correct for every frame of a movie without inspecting any of them — which matters because a movie's legend *must* be fixed: it affects the figure height, and H.264 requires constant frame dimensions.

Row order follows the config's own cell-type order.

**Behavioral specification (core):**
- `storyboard(panels; backend=:svg, ncols=length(panels), panel_width=300, title_height=34, pad=12, output="storyboard.svg", overwrite=false)`.
- Panels are an **ordered** sequence; laid out row-major, defaulting to a **single row** (`ncols = n`). `ncols` wraps into a grid while preserving time order.
- Each panel's title is exposed (where timestamps go). Frame-sequence (animated) panels are rejected — storyboard is static.
- Shares the `_svgGrid(panels; ncols, …)` builder with `montage`. Writes by default (`storyboard.svg`), `output=nothing` returns the string, same overwrite guard.

**PCMM extension** (`storyboard(::Type{Simulation}, sim_id; …)`): operates on **one** simulation. Timepoints via `index` (a vector of `Integer` snapshot indices and/or `:initial`/`:final`) **or** `n_snapshots` (default 4: evenly-spaced spanning the run, including endpoints). `n_snapshots` defaults to `length(index)` when `index` is given; passing both with different lengths errors. Frame titles are the snapshots' simulation times via a `title` function (default `t -> "t = $t"`). Writes under `dataDir()/outputs/storyboard.svg` by default.

**Acceptance criteria:**
- `storyboard(Simulation, sim_id)` writes a single-row filmstrip of 4 evenly-spaced, timestamp-titled frames. ✓ verified on the dev project.
- Core works with no PCMM, given hand-written ordered panels.

---

## Feature: Cell-type legend for `montage` / `storyboard` — **implemented 2026-08-05**

**One-line description:** Draw a cell-type legend alongside a stitched-SVG composition, built from the cell types the composition actually shows.

**Priority:** Should-have (a montage of colored cells is unreadable without a key).

**Where the entries come from:** the snapshot SVGs tag every cell — `<g id="cell442" type="tumor_epi" dead="false">` wrapping two `<circle>`s — so the label is the `type` attribute and the color is the outer circle's `fill`. Deriving the legend from the figure's own content means it lists exactly what is on screen, needs no side file, and stays correct automatically when panels are filtered. Dead cells are drawn black regardless of type, so they are skipped when sampling a type's color and contribute a single `dead` entry when present.

*(PhysiCell also writes its own `output/legend.svg`. It is **not** used: it lists every configured cell type whether shown or not, its 1440×260 aspect wastes vertical space, and as a nested `<svg>` it is awkward to edit in Illustrator/PowerPoint. It remains available via `legend="…/legend.svg"`.)*

**Behavioral specification (core):**
- `_svgGrid` gains `legend_svg` / `legend_position` / `legend_font_size`; the verbs expose the single user-facing `legend` (plus `legend_file`, `legend_font_size`), normalized by `_normalizeLegend`.
- `legend` accepts: `nothing`/`false` (none — the core default), **`(label, color)` entries**, an SVG **path or string**, `:auto`, `:bottom`, `:top`, or a `(row, col)` / `(row, col, span)` cell. Empty entries mean no legend.
- **Drawn legends** (`_svgLegend`) emit **flat top-level `<circle>` and `<text>`** — deliberately not a nested `<svg>`, since nested SVGs are what PowerPoint and Illustrator handle worst and hand-editability is a main reason the output is SVG. They are authored at `legend_font_size` (the title size by default) and **wrap** to fit the space given, never scaling the text. So there is no scale factor and no minimum-legibility problem. The layout is run against the width the legend was *sized* against, never its own used width — re-wrapping at exactly that width lands the final entry on a float equality boundary and can push it onto a row the reserved band has no height for.
- **External legend SVGs** are nested at natural size, shrunk only if they will not fit.
- **`:auto` placement:** the free cells trailing the last row, spanning the whole run, costing *no* space; else a full-width band below. Always safe for a drawn legend (it wraps); an external SVG takes the run only if it is at least 0.7 of the run width, else bands.
- Emitted legend geometry is rounded (`_px`); **with `legend_svg === nothing` output is byte-identical** to a grid built with no legend support.
- **Movies:** `MontageSpec` carries the legend so every frame draws the same one. A five-argument constructor preserves the old arity (no legend).

**PhysiCellOutput extension:** `legend=:auto` is the **default**. `_legendEntries` reads each folder's `legend.svg` (`_legendRows`) and unions across folders, so a sweep that mixed configs still explains every type any panel can contain — verified on the dev project, where 52 sims define 4 cell types and 12 define a 5th (`filler`). Folders with no `legend.svg` contribute nothing; if none has one, there is no legend. PCMM inherits this unchanged.

**Acceptance criteria:**
- `storyboard(seq)` puts a compact legend band below the filmstrip, text matching the titles. ✓ verified on the dev project (one 37.4 px row, i.e. 49.4 px total — a third of what nesting `legend.svg` cost) and rendered.
- A montage with a free cell run places the legend there at **no size cost**, wrapping as needed. ✓ verified (3-sim montage, dimensions identical with and without).
- Entries are the config's cell types, unioned across panels. ✓ verified: a 64-sim montage across mixed configs picks up `filler`, which only 12 sims define.
- A movie's legend is complete and identical in every frame, built without reading a single snapshot. ✓ verified over 121 frames.
- `legend=nothing` is byte-identical to the pre-feature output. ✓ core test.

---

## Feature: `tableau` — CairoMakie backend **(implemented incl. movies, 2026-07-23)**

**One-line description:** Compose a single simulation state as a focal panel with satellite panels arranged around it.

**Priority:** Must-have (forces the CairoMakie path).

**Resolved design (2026-07-22):**
- **Auto-ring layout:** focal panel centered; satellites auto-placed around it (a grid ring), count-dependent. Explicit positions are a later option.
- **Focal = cell scatter re-plotted from data** (`scatter!`, colored by cell type), in the same axis coordinates as the satellite heatmaps → a true shared spatial extent.
- **Satellites = one `heatmap!` + `Colorbar` per substrate** (voxel grid reshaped from the `substrates` DataFrame).
- **CairoMakie-only, data-driven** — no SVG stitching. Static **and animated** (a movie animates the whole scene over a snapshot sequence via `Makie.record`, decided by the `index` value). A `:makie` backend for `montage`/`storyboard` was considered and **declined** — no added value; those verbs stay SVG-only.

**Architecture — two extensions (composed); the data-agnostic work lives in the CairoMakie ext:**
- `MontageCairoMakieExt` (weakdep `CairoMakie`): the **public generic `tableau(focal, satellites; …)`** — `focal`/`satellites` are axis callbacks; it owns everything data-agnostic: `Figure`/`GridLayout`, center focal + auto-ring satellites (`_ringSlots`), shared axes, `Colorbar`s, legend placement (`_placeLegend!`), and output-writing. (`_tableauFigure` is a private layout helper here.)
- `MontageCairoMakiePCMMExt` (weakdeps `CairoMakie` **and** `PhysiCellModelManager`): `tableau(::Type{Simulation}, sim_id; …)` — a **thin adapter**: pulls cells/substrates from `PhysiCellSnapshot`, builds the scatter/heatmap callbacks (`_substrateGrid` reshapes the voxel grid), then delegates to the generic `tableau`. PhysiCell-specific code only.
- Core declares + exports `tableau` with a fallback erroring "run `using CairoMakie, PhysiCellModelManager`".

**API:**
- Generic: `tableau(focal, satellites; focal_title, satellite_titles, colorbar_labels, xlims, ylims, legend, size, output="tableau.png", overwrite)` — data-agnostic, callback-based.
- PhysiCell: `tableau(::Type{Simulation}, sim_id; index=:final, substrates=<all>, colormap=:viridis, markersize, legend=:auto, size, framerate=15, output=<dataDir()/outputs/tableau.png|.mp4>, overwrite=false)`. The **`index` value decides still vs. movie** (same as `montage`): `:final`/`:initial`/`Integer` → a still; `:all` or a vector/range of snapshot indices → a **movie** (the scene animated over those snapshots via `Makie.record`; colorranges fixed globally per substrate for a stable colorscale; the cell-type set is the union across frames). Writes by default (`.png` still / `.mp4` movie), overwrite guard; for a still `output=nothing` returns the Makie `Figure` (a movie needs a path). `legend` places the cell-type legend (`:auto` → an empty grid cell off the plot; a corner `Symbol`; a `(row,col)`; or `nothing`). Also accepts a `Simulation`/`PCMMOutput{Simulation}` object.

**Acceptance criteria:**
- `tableau(Simulation, sim_id)` renders the cell scatter centered with one heatmap+colorbar per substrate around it, on a shared spatial extent, and writes a `.png`. ✓ verified on the dev project.
- `tableau(Simulation, sim_id; index=:all)` writes an `.mp4` animating the scene over the snapshots, with a stable colorscale and legend and an animated `t = …` title. ✓ verified on the dev project.

---

## Feature: Movies (orthogonal time axis)

**One-line description:** Render a composition as an animation over a time dimension.

**Priority:** Must-have (headline feature).

**Behavioral specification:**
- `montage` movie = every sim panel animates through time **simultaneously** → compare dynamics across sims. **(In progress — the first movie feature.)**
- `storyboard` is **static only** (a filmstrip) — for a single-simulation *movie*, animate one simulation's frames with `montage` (a scalar id is accepted: `montage(Simulation, id; index=:all)`).
- `tableau` movie = the whole composed scene animates through time together. *(later, CairoMakie path)*
- **API:** the **panel content decides still vs. movie** — if any panel's content is a frame sequence, `montage` renders a movie **in one call** (writing `.mp4`), auto-picking the output extension. `output=nothing` returns a [`MontageSpec`](@ref) instead, which `record(spec, path; framerate, scale, overwrite)` animates (the underlying renderer + an escape hatch for finer control). No per-verb `movie=` kwarg or `_movie`/`_gif` variants.
- **Two rendering paths:**
  - **SVG-frame path (default, Option A):** for each timepoint, compose the montage SVG of that timepoint's frames via the core `_svgMontage`, rasterize (Rsvg + Cairo), and encode the PNG sequence with FFMPEG. Preserves exact PhysiCell styling; reuses the SVG backend; no CairoMakie. Lives in `ext/MontageMovieExt.jl` (weakdeps `Rsvg`, `Cairo`, `FFMPEG`). **This is the path used for the montage-of-movies feature.**
  - **CairoMakie path:** `Makie.record` for `tableau` movies (data-driven; scene animated over a snapshot sequence). Implemented in `MontageCairoMakiePCMMExt`.
- **`MontageSpec`** (core type): a grid of frame-sequence panels + a common frame count + layout params. `montage` builds it internally (and returns it when `output=nothing`); `_svgFrame(spec, t)` renders one timepoint's montage SVG.
- **Frame alignment across sims:** by **frame index**, truncated to the shortest sequence, with a warning when lengths differ. Time-based alignment (nearest snapshot on a common time grid) is a **planned follow-up** — see the to-do in progress.md.

**Acceptance criteria:**
- `record(montage(frame_panels), "out.mp4")` writes a playable video with `nframes` frames at the requested framerate, each frame the montage of that timepoint.
- Calling `record` without the movie extension loaded errors with a message to `using Rsvg, Cairo, FFMPEG`.

---

## Feature: PCMM Extension

**One-line description:** Add convenience methods that resolve PhysiCell simulation ids to files, loaded only when PCMM is present.

**Priority:** Must-have (this is how the tool is actually used in practice).

**Planned refactor (stays in Montage):** add a **folder-path front door** so non-PCMM PhysiCell users are supported — a `MontagePhysiCellOutputExt` (weakdep `PhysiCellOutput.jl`) exposing `montage(PhysiCellOutput(path))` etc. The PCMM id door (`MontagePhysiCellModelManagerExt`, `MontageCairoMakiePCMMExt`) becomes a **thin adapter that delegates** to the folder-path methods (id→folder→`PhysiCellOutput`), so both front doors share one code path and everyone still types `using Montage`. `montage(::Type{Simulation})` **stays in Montage** — not a breaking change. See [CLAUDE.md](CLAUDE.md) To-dos "PhysiCell support stays in Montage".

**Status:** `montage(::Type{Simulation}, …)` **implemented (2026-07-21)**, `storyboard(::Type{Simulation}, sim_id; …)` **implemented (2026-07-22)**, and `tableau(::Type{Simulation}, sim_id; …)` incl. movies **implemented (2026-07-23)**.

**Behavioral specification:**
- Ships as `ext/MontagePhysiCellModelManagerExt.jl`, wired via `[weakdeps]` + `[extensions]` in `Project.toml`. Triggered by **PhysiCellModelManager** (the added knowledge is the PhysiCell output-file convention), though `Simulation`/`simulationIDs`/`trialFolder`/`dataDir` are ModelManager's, re-exported by PCMM.
- `montage(::Type{Simulation}, sim_ids; index=:final, title=(id->"Sim $id"), panel_width=300, title_height=34, pad=12, output::Union{Nothing,AbstractString}=<auto>, overwrite=false, framerate=15)`. `sim_ids` is required — `simulationIDs()` covers "all sims" explicitly; there is no all-sims default. The **`index` value decides still image vs. movie** (one opinionated call that produces output; no separate `frames` kwarg).
  - **Still image** (`index` is `:final`/`:initial`, or an Integer): one panel per sim selected the same way as PCMM's `PhysiCellSnapshot` — a Symbol names the state SVG, an Integer selects that indexed snapshot (`snapshotNNNNNNNN.svg`). Missing files skipped with a warning. Writes an SVG.
  - **Movie** (`index` is `:all` or a vector/range of snapshot indices): each panel plays that sim's snapshot sequence (index-aligned, truncated to shortest); rendered via `record` (requires the movie extension).
  - **Output:** `output` defaults to `dataDir()/outputs/montage.svg` (still) or `…/montage.mp4` (movie), erroring if it exists unless `overwrite=true`. `output=nothing` returns the in-memory result — the SVG string (still) or a `MontageSpec` (movie). `framerate` applies to movies.
- `storyboard(::Type{Simulation}, sim_id; index=nothing, n_snapshots, title=(t->"t = $t"), ncols, panel_width, title_height, pad, output=<dataDir()/outputs/storyboard.svg>, overwrite=false)` — one simulation's time filmstrip; see the `storyboard` feature above for `index`/`n_snapshots` semantics and timestamp titles.
- **Convenience input overloads** (resolve to constituent simulations, then forward):
  - `montage` accepts a scalar `Integer` id, a trial (`::AbstractTrial` — `Simulation`/`Monad`/`Sampling`/`Trial`), a `::PCMMOutput`, or a vector of either (`AbstractVector{<:AbstractTrial}` / `AbstractVector{<:PCMMOutput}`) — via `simulationIDs`.
  - `storyboard` (single-sim) accepts a `::Simulation` object or a `::PCMMOutput{Simulation}` (single-simulation run output).
- File resolution uses `trialFolder(Simulation, id)/output/` (`final.svg`, `initial.svg`, `snapshot00000000.svg …`); snapshot **times** come from `PhysiCellSnapshot(sim_id, index).time` (metadata only). Full data-driven primitives (`substrates`/`cells` DataFrames) are reserved for the future `tableau`/data-movie path.
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
