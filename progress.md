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
- Committed (`52c27e8`) and merged to `main`. `HANDOFF.md` removed (`c7061ba`).
- `Project.toml` still has no `[weakdeps]`/`[extensions]` — added with the movie/PCMM slices.

---

## Session: montage-of-movies — `record` via SVG frames + FFMPEG (2026-07-21)

### Goal
The headline feature: a `montage` whose panels are **movies**, all playing in lockstep → one `.mp4` comparing dynamics across sims. Branch `feature/montage-movie`.

### The fork we resolved (with the user)
Two ways to render movie frames; the user chose **Option A**:
- **Option A (chosen) — SVG frames + FFMPEG, no Makie.** Each timepoint = the static montage of that timepoint's frames (reuse `_svgMontage`), rasterized (Rsvg + Cairo) and encoded (FFMPEG). Reuses shipped code, exact PhysiCell styling, lightest deps.
- **Option B — CairoMakie `Makie.record`.** Deferred; CairoMakie earns its place later for `tableau` and true data-driven/heatmap movies, where its layout engine + colorbars matter. This feature doesn't need them.

This **revises the earlier assumption** that "movies = CairoMakie extension." Movies are now split: montage-of-movies rides the SVG backend (`MontageMovieExt`); CairoMakie is a later, separate path.

### Decisions
- **`record` is a separate entry point** (not a per-verb `movie=` kwarg). Core owns `record(spec::MontageSpec, path; framerate)`; the real renderer lives in `ext/MontageMovieExt.jl` and is reached via the core hook `_recordSVGMovie` (untyped fallback in core errors until the ext loads — the ext adds a more-specific method, so no method-overwrite).
- **`MontageSpec`** (core type): frame-sequence panels + common frame count + layout params. `montage(panels)` returns a `MontageSpec` when any panel's content is a `Vector` of frame paths; otherwise it returns the SVG string as before (additive, static API unchanged). `_svgFrame(spec, t)` builds one timepoint's montage SVG by reusing `_svgMontage`.
- **Frame alignment: by index, truncate to shortest**, warn on unequal lengths. Time-based alignment is a logged **follow-up** (see PRD "Still open").
- **Deps (user-approved):** `Rsvg`, `Cairo`, `FFMPEG` as `[weakdeps]`; single `[extensions]` entry `MontageMovieExt`. Core stays dependency-free.
- **Backend fallback fix:** generalized the `:makie` fallback in `montage_verb.jl` to dispatch on the abstract `MontageBackend` (not concrete `MakieBackend`) so the future CairoMakie extension can add the concrete method without a method-overwrite warning. Same pattern used for `_recordSVGMovie`.

### Testing
- Committed core tests stay dependency-free: `MontageSpec` construction, index truncation + length-mismatch warning, `_svgFrame` output, and the `record` fallback error. **The heavy deps stay out of the core test target.**
- End-to-end movie render (Rsvg/Cairo/FFMPEG) verified **manually** this session in a scratch env, not in the committed suite (per the "no heavy deps in core tests" rule).

---

## Session: PCMM convenience extension — `montage(Simulation, …)` (2026-07-21)

### Goal
Collapse the manual snapshot-path assembly (seen in the dev project's `GenerateData.jl`) into a one-liner: with PCMM loaded, `montage(Simulation, ids; index=…)` resolves each sim's output SVGs into panels — a still-image grid or a movie, decided by the `index` value. Branch `feature/pcmm-ext`.

### Extension direction (decided with the user)
**Montage hosts the extension** (`ext/MontagePhysiCellModelManagerExt.jl`, PCMM as weakdep), not PCMM hosting one for Montage. Rationale: the method extends Montage's own `montage` (its public API), the viz→data dependency direction is the correct one, the glue co-locates with the churning package, and CLAUDE.md treats PCMM as read-only. Both directions are legal (no piracy — PCMM owns `Simulation`); this is a coupling call.

### Key facts that shaped it
- `Simulation`, `simulationIDs`, `trialFolder`, `dataDir` are **ModelManager's**, re-exported by PCMM (`@reexport using ModelManager`). The extension triggers on **PhysiCellModelManager** anyway, because the knowledge added is the PhysiCell `.svg` output-file convention (`output/final.svg`, `output/snapshotNNNNNNNN.svg`), which ModelManager (simulator-agnostic) lacks.
- PCMM already has `makeMovie(sim_id)` (single-sim, ImageMagick+FFmpeg). Montage's montage-of-movies is the complementary **cross-sim grid** — no conflict.
- The dev project's `GenerateData.jl` already hand-builds `framesA`/`framesB` + `Panel` + `record(...)`; the extension's `index=:all` (one call) replaces that whole block.

### API (resolved with the user)
`montage(::Type{Simulation}, sim_ids; index=:final, title=(id->"Sim $id"), panel_width=300, title_height=34, pad=12, output=_defaultOutput(index), overwrite=false, framerate=15)`. `sim_ids` is **required** (no all-sims default — use `simulationIDs()` explicitly).
- **One kwarg decides still vs. movie (user's fusion, superseding the earlier `frames`/`index` split):** `index` = `:final`/`:initial`/Integer → still image (matches PCMM's `PhysiCellSnapshot`); `index` = `:all` or a vector/range of indices → movie. No separate `frames` kwarg.
- **Writes by default** (user preference: "users call this to see the output"). `output::Union{Nothing,AbstractString}` defaults to a **computed real path** (`_defaultOutput(index)` → `…/montage.svg` still or `…/montage.mp4` movie), so there is **no "not-given" sentinel** — a path overrides. `output=nothing` uniformly means "don't write, return the in-memory result": the SVG string for a still image, or a `MontageSpec` for a movie. (Refined from an earlier `missing`/`nothing` two-sentinel design, which was confusing — the single `nothing` + type annotation is clearer and rejects non-path values with a `TypeError`.)
- **Overwrite guard:** error if `output` exists unless `overwrite=true`, for both still and movie writes.
- **The PCMM method is now a thin wrapper over core `montage`** — it just builds panels (a state SVG per sim, or a frame sequence per sim) and hands them to core, which does everything below.

### Core `montage`/`record` unified too (user's follow-up: "unify the record call in core")
The write-by-default + one-call-movie behavior was pushed **into the core**, so core and PCMM behave identically (only the default *location* differs — core → cwd, PCMM → `dataDir()/outputs`):
- **Core `montage(panels; …, output=_defaultOutput(panels), overwrite=false, framerate=15)`** now decides still vs. movie from **panel content** (`_looksAnimated`): all-single-image → SVG; any frame-sequence panel → movie rendered **in one call** via `record`. Writes by default to `montage.svg`/`montage.mp4` in cwd. `output=nothing` returns the in-memory result (SVG `String` or `MontageSpec`) — the composable escape hatch, and the only movie path that works without the movie extension loaded.
- **Core `record(spec, path="montage.mp4"; framerate, scale, overwrite)`** gained a default path + the overwrite guard. It stays the underlying renderer (and public, for hand-built specs / `output=nothing` results).
- **Shared `_assertWritable(path, overwrite)` lives in core** and guards every write (`montage` static, `record`); the PCMM ext dropped its private copy and just passes `output`/`overwrite` down.
- This **supersedes the movie-session decision** that `montage` always returns a `MontageSpec` for `record` (the strict two-call contract): the two-call flow is now the `output=nothing` opt-in, not the default.

### Wiring
- `Project.toml`: added `PhysiCellModelManager` (UUID `7582d1aa-…`) to `[weakdeps]`, `MontagePhysiCellModelManagerExt = "PhysiCellModelManager"` to `[extensions]`, `PhysiCellModelManager = "0.3"` to `[compat]`. Montage must be registered in **BergmanLabRegistry** (where PCMM lives), not General — CI/TagBot/CompatHelper were wired to that registry in a prior commit.

### Testing / verification
- Core tests unchanged and green (36/36); the PCMM weakdep declaration doesn't disturb core resolution.
- **No PCMM in the core test suite** (heavy; needs a live project). Verified **manually** against the `GeorgetownR01` dev project: still images for `index=:final`/`:initial`/Integer; bad `index` symbol and bare `montage(Simulation)` error correctly; `index=:all` writes a correct 2×2 movie in one call (sims synchronized by time, PhysiCell styling intact); overwrite guard throws.

### Note
- Verified the extension loads via `Base.get_extension` and that `record` still errors helpfully when the movie deps aren't also loaded (the two extensions are independent).

### Docs locality (decision + follow-up)
Code-locality and docs-locality are separate: the extension *code* rightly lives in Montage (it extends Montage's `montage`; dependency points viz→data), but the *user-facing tutorial* for `montage(::Type{Simulation}, …)` has a **PCMM audience** — those users look in PCMM's docs, not in a viz dependency. A generic Montage user (arbitrary SVGs, no PCMM) shouldn't be led through `Simulation` details.

Resolution:
- The extension method's **docstring stays in Montage** (technical necessity — Documenter/`?` pull it from where the method is defined) and belongs under a clearly-labeled "PhysiCellModelManager extension" heading in Montage's API reference. Reference ≠ tutorial.
- Montage's user docs stay **generic-first**; PCMM is a short "if you use PCMM…" pointer. Per user's call (2026-07-21), the **fuller worked example in the README is kept for now** and will be slimmed to a pointer only once PCMM has its own page.
- The real how-to — a **"Visualizing simulations with Montage"** page (tutorial for `montage(Simulation)` / `record`, linking back to Montage's API reference) — **belongs in PCMM's docs**. We can't author it from here (PCMM is a read-only boundary / separate repo), so it's a cross-repo follow-up for a PCMM session (see the handoff to-do in CLAUDE.md).

---

## Session: `storyboard` — static filmstrip (2026-07-22)

Branch `feature/storyboard`. The third verb, static-only.

### Scope decision (user)
`storyboard` is **static only** — a filmstrip for a poster/paper. `montage` already does
movies (montage-of-movies), and `tableau` will do sophisticated ones; a single-simulation
movie is just `montage(Simulation, [id]; index=:all)`. So storyboard has **no movie path**.

### What was built
- **`_svgMontage` → `_svgGrid(panels; ncols=ceil√n, …)`** (rename + add `ncols`). Now shared
  by `montage` (ncols = ceil√n), the movie `_svgFrame` (ncols = ceil√n), and `storyboard`
  (ncols = n → single row). Also extracted `_writeSVG(svg, output, overwrite)` (dispatch on
  `::Nothing`/`::AbstractString`) shared by the SVG-backend verbs.
- **`src/storyboard.jl`** — `storyboard(panels; backend=:svg, ncols=length(panels), …,
  output="storyboard.svg", overwrite=false)`. Ordered, single-row default; rejects animated
  panels (static). Writes by default; `output=nothing` returns the string. Same backend
  dispatch as montage (`:makie` errors on the abstract fallback).
- **PCMM ext `storyboard(::Type{Simulation}, sim_id; …)`** — one sim. `index` (vector of
  `Integer`/`:initial`/`:final`) **or** `n_snapshots` (default 4, evenly-spaced incl.
  endpoints via `_evenSnapshots`). Titles = snapshot times via `PhysiCellSnapshot(sim_id,
  sel).time` (metadata only), through a `title` function (default `t -> "t = $t"`).

### Key decisions
- **`index`/`n_snapshots` interaction (user's design, adopted):** `n_snapshots::Integer =
  isnothing(index) ? 4 : length(index)`. So the user passes only one; no `n_snapshots=nothing`
  ceremony. If both are passed with different lengths → throw. `index` present ⇒ it wins.
- **Timestamp titles default to raw time** (`"t = $t"`, PhysiCell minutes) — user's call;
  a custom `title` function reformats (e.g. minutes→days). Robust fallback to a selector
  label if a snapshot's time can't be read (`PhysiCellSnapshot` returns `missing`).
- **File-vs-metadata naming gotcha:** PhysiCell writes SVG frames as `snapshotNNNN.svg` but
  metadata as `outputNNNN.xml`; `PhysiCellSnapshot(sim_id, i).time` reads the XML, so times
  resolve for both integer indices and `:initial`/`:final` (all present in the dev project).

### Verification
- Core tests 49/49 (added storyboard geometry/ordering/ncols/guard tests). No heavy deps.
- PCMM `storyboard(Simulation, 1)` on the dev project → a 1×4 filmstrip at t = 0/2400/4800/7200,
  each timestamp-titled, tumor growing 300→510 agents; rendered and eyeballed. `n_snapshots`,
  explicit `index` with `:initial`/`:final`, the mismatch throw, and a custom `title` all verified.

### Docs
- PRD `storyboard` feature marked implemented; Movies feature notes storyboard is static;
  README usage + Implementation Status updated; PCMM handoff (`PCMM_DOCS_HANDOFF.md`, drafted
  this session) has `montage`/`storyboard` sections ready, `tableau` still a stub.

### Next
- `tableau` + the CairoMakie extension (`:makie` backend, real heatmaps/colorbars). Then
  finish the handoff's tableau section and hand off to a PCMM session.

### Input-type overloads (user request, same session)
Both verbs now accept PCMM objects, not just ids — each resolves to constituent simulations
via `simulationIDs` and forwards:
- `montage`: scalar `Integer`, `::AbstractTrial` (Simulation/Monad/Sampling/Trial), `::PCMMOutput`,
  and vectors of either (`AbstractVector{<:AbstractTrial}` / `AbstractVector{<:PCMMOutput}`).
- `storyboard` (single-sim): `::Simulation` object, `::PCMMOutput{Simulation}`.

Types: `AbstractTrial` (ModelManager, re-exported), `const PCMMOutput = MMOutput{T<:AbstractTrial}`
with a `.trial` field. Dispatch is unambiguous — these instance/vector methods are more
specific than the core `montage(panels::Any)`, and SVG-path vectors (`Vector{String}`) still
route to core. Verified on the dev project (trial objects, output objects, vectors of each);
core tests unaffected (49/49).

---

## Session: `tableau` + CairoMakie backend (2026-07-22)

Branch `feature/tableau`. The last verb — CairoMakie-only, data-driven. Design resolved with
the user: **auto-ring** layout (focal centered, satellites around), focal = **cells re-plotted
as scatter** (shared axis with the heatmaps), **CairoMakie weakdep, static v1** (tableau movies
deferred; a `:makie` backend for montage/storyboard was later declined — no added value).

### Architecture — two composed extensions
- Core declares + exports `tableau` (fallback errors "run using CairoMakie, PhysiCellModelManager")
  and declares `function _tableauFigure end` (the layout-engine hook).
- `MontageCairoMakieExt` (weakdep CairoMakie): implements `_tableauFigure(focal, satellites; …)` —
  `Figure`/`GridLayout`, focal centered via `_ringSlots`, satellites ringed each with an `Axis`
  + `Colorbar`, shared `limits!`/`DataAspect`. Data-agnostic; takes axis-callbacks.
- `MontageCairoMakiePCMMExt` (weakdeps CairoMakie + PhysiCellModelManager): `tableau(::Type{Simulation},
  sim_id; time, substrates, colormap, …)` — loads `PhysiCellSnapshot` cells+substrates, builds the
  callbacks (scatter cells by `cell_type_name`; `heatmap!` each substrate on the reshaped voxel grid),
  calls `_tableauFigure`, writes the figure. Cross-ext call works because loading PCMM+CairoMakie
  loads both exts, and `_tableauFigure` is core-owned.

### Data facts (from the dev project, sim 1)
- Cells DataFrame: `position_1`/`_2`/`_3`, `cell_type` (Int), `cell_type_name` (String, e.g. "tumor_epi").
- Substrates DataFrame: `["x","y","z","volume", <names…>]` → substrate names = columns after `volume`
  (here debris/ecm/oxygen). One row per voxel; grid 50×50×1 (2D). Reshape to a matrix via an explicit
  (x,y)→index pivot (robust to voxel ordering). `substrateNames` is NOT exported — derive from columns.
- Mesh: `x`/`y`/`z`/`bounding_box`; x,y span −490…490 (50 pts each) → shared axis limits.

### Implementation + verification
- Core: `src/tableau.jl` (declares/exports `tableau` + fallback; declares `_tableauFigure`).
- `ext/MontageCairoMakieExt.jl` — `_ringSlots` + `_tableauFigure`. `ext/MontageCairoMakiePCMMExt.jl`
  — `tableau(::Type{Simulation}, sim_id; time, substrates, colormap, markersize, size, output,
  overwrite)` + `Simulation`/`PCMMOutput{Simulation}` object forms. `_substrateGrid` pivots the
  voxel column to a matrix (Base-only; **no `using DataFrames`** — property access + `propertynames`).
- `Project.toml`: `CairoMakie` weakdep + the two `[extensions]` entries + compat `0.15`.
- Core tests still 49/49 (tableau core is just a declaration; heavy deps stay out of the suite).
- **Verified** in a scratch env (Montage-dev + PCMM + CairoMakie), `initializeModelManager` on the
  GeorgetownR01 project: `tableau(Simulation, 1)` rendered a correct scene — cells (caf/nk/tumor_epi/
  tumor_mes) centered with a legend, `debris`/`oxygen`/`ecm` heatmaps ringed around, colorbars, shared
  extent; oxygen depleted in the tumor core, ecm ring at the periphery (biologically coherent). The
  substrate-subset, object-input, and `output=nothing` (returns `Figure`) forms also work.

### Gotchas / notes
- Both exts load whenever CairoMakie(+PCMM) are present; `MontageCairoMakiePCMMExt` calls the
  core-owned `Montage._tableauFigure` (implemented in `MontageCairoMakieExt`) — clean cross-ext call.
- `substrateNames` is **not exported** by PCMM; derive substrate columns from `propertynames(subs)`
  minus `("x","y","z","volume")`.
- CairoMakie is heavy to precompile in a fresh env (~minutes); it was already in the depot.

### Next
- `tableau` movies (`Makie.record` over `time`) are the remaining verb follow-up. (A `:makie`
  backend for `montage`/`storyboard` was declined — no added value.) The PCMM docs handoff
  (`PCMM_DOCS_HANDOFF.md`) now has all three verb sections ready to carry to a PCMM session.

### Follow-up refinements (same session)
- **Legend not visible over dense cells** → added a `legend` kwarg. Placement moved out of the
  focal callback into the layout engine (which knows the grid): `:auto` (default) puts the legend
  in an empty grid cell *off the cell plot*, falling back to an opaque in-axis corner if the grid
  is full; a position `Symbol`, an explicit `(row,col)`, or `nothing` are also accepted.
- **Docstring locality** → the detailed PCMM behavior moved onto the `tableau(::Type{Simulation},…)`
  method docstring (in the ext); the core `tableau` docstring stays generic. Matches montage/storyboard.
- **Shifted data-agnostic work out of the PCMM ext** → promoted a **public generic
  `tableau(focal, satellites; …)`** into `MontageCairoMakieExt` that owns layout + colorbars +
  legend + output. `MontageCairoMakiePCMMExt` is now a thin adapter (PhysiCell data → callbacks →
  generic `tableau`); `_tableauFigure` is a private helper of the CairoMakie ext (the core
  `_tableauFigure` hook was removed). Verified: PCMM path unchanged, and the generic `tableau`
  composes arbitrary callbacks standalone (scatter + heatmaps, legend auto-placed).

---

## Session: `tableau` movies + `time`→`index` (2026-07-23)

Branch `feature/tableau-movies`.

### API fix (user caught the inconsistency)
tableau's snapshot selector was named `time`, but `montage`/`storyboard` (and PCMM's
`PhysiCellSnapshot`) use `index`. Renamed `time`→`index` so all three verbs match. The
`index` value decides still vs. movie, exactly like `montage`: `:final`/`:initial`/`Integer`
→ still; `:all` or a vector/range → movie.

### How the movie is built (reuses the generic engine)
No new generic API. In `MontageCairoMakiePCMMExt._tableauMovie`:
- Load the selected snapshots; build **Observables** — per-cell-type position vectors, per-
  substrate matrices, and an animated title `Observable{String}`.
- Build focal/satellite callbacks that plot those Observables, then call the generic
  `Montage.tableau(focal, satellites; output=nothing)` — **reuses the whole layout engine**
  (auto-ring, colorbars, legend) to build the Figure once.
- `CairoMakie.record(fig, path, eachindex(frames)) do k; update the Observables to frame k; end`.
- To make the animated title work, loosened the generic `focal_title` type (String → any, so an
  `Observable` passes through to `Axis(title=…)`).

### Correctness decisions (confirmed with the user)
- **Fixed global colorrange per substrate** (min/max across all frames) → a stable, comparable
  colorscale (no flicker). Constant-field guard: expand a zero range by one.
- **Union of cell types across frames** → stable legend + stable per-type colors.
- `output=nothing` returns a Figure for a *still*; a *movie* requires a path (errors on nothing).
  Default output extension is `.mp4` (movie) vs `.png` (still), keyed on `_isMovieIndex(index)`.
- **No new dependency:** Makie handles video encoding; the FFMPEG weakdep is only for the
  SVG-frame montage-of-movies path.

### Verification
- Core tests 49/49 (tableau movie is ext-only; heavy deps stay out of the suite).
- `tableau(Simulation, 1; index=0:20:120)` on the dev project wrote a correct `.mp4`: title
  animates `t=0 → 6000`, cells grow, substrates evolve (oxygen depletes in the tumor core, ecm
  ring forms), colorscales fixed across frames, legend stable. Still `index=:final` also verified.

### Note
- `:makie` backend for `montage`/`storyboard` was **declined** (no value). The `backend`
  kwarg + `MakieBackend` selector on those verbs are now vestigial scaffolding (candidate for a
  future cleanup).

### Naming: `tableau` vs. `dashboard` (resolved)
Considered renaming `tableau` → `dashboard`. Resolution: **keep `tableau`** (composition-register
cohesion with montage/storyboard; precise for a focal-centric composed scene, not a uniform grid;
"dashboard" connotes interactive/live monitoring, which the static/movie figure isn't). And
**reserve `dashboard`** for a *future, distinct* verb — a live-updating/interactive counterpart
built on the same Observable-driven layout engine (drive `_tableauFigure` from a running sim's
output or a time slider instead of a recorded frame loop). So the two words become two features,
not a rename. See CLAUDE.md To-dos.

---

## Session: cell-type legend for `montage` / `storyboard` (2026-08-05)

Branch `feature/svg-legend`. First of five to-do items; the only one with real core changes.

### Two wrong turns, worth recording so they are not repeated
The final design — parse PhysiCell's `legend.svg` for `(label, colour)` pairs and **draw** the
legend ourselves — was reached only after two detours, both from bad framing on my part.

**Detour 1: nesting `legend.svg` as an image.** The first implementation embedded `legend.svg`
as a scaled nested `<svg>`, on the reasoning that its colours come from PhysiCell's *compiled*
coloring function and `PhysiCellOutput` exposes no colour data — so it looked like the only
faithful source. The user corrected the premise: **faithfulness to PhysiCell's legend was never a
goal — we just need *a* legend.** Nesting it was also actively bad, because a nested `<svg>` is
what PowerPoint and Illustrator handle worst, and hand-editability is a large part of why the
output is SVG at all. Costs of that version: a font-ratio scale factor
(`_svgFontSize`/`_legendFontScale`/`_legendScale`), a minimum-legibility floor
(`_LEGEND_AUTO_FIT_FLOOR`, because a 1440-wide legend in one 300 px cell rendered text at
**8.85 px** against 22 px titles), and a wasteful band (147 px for content needing 49 px).

**Detour 2: deriving entries by scanning snapshot SVGs.** Freed from `legend.svg`, I noticed the
snapshots tag every cell (`<g id="cell442" type="tumor_epi" dead="false">`) and derived the legend
from those instead. That fixed the drawing problems but replaced them with a *sampling* problem:
cost scaled with **frames**, so a fixed movie legend needed a heuristic (3 frames per panel) that
could miss a transient type — and scanning exhaustively measured **59 s / 8.9 GB** for a 64-panel
movie. The user pointed out the actual answer: this code is PhysiCell-only, `legend.svg` is right
there with names *and* colours, and the legend should describe **what the config says the model can
contain**, not what happens to be visible. Cost then scales with *simulations*, not frames:
**13.9 ms / 97 KB for 64 sims**.

Both detours shared one mistake: treating "reuse PhysiCell's legend file" and "build our own
legend" as mutually exclusive. The right answer uses the file as a *data source* and does the
drawing itself.

### What the final design gets
- **No scale factor, no legibility floor.** Drawn at the title font size, wrapping to fit.
  `_svgFontSize`, `_legendFontScale`, `_legendScale`, `_LEGEND_AUTO_FIT_FLOOR` all deleted.
- **Config order for free** — `legend.svg` rows are in cell-type order, better than sorting by name.
- **Movies need no frame inspection.** A movie legend *must* be fixed (it affects figure height,
  and H.264 requires constant frame dimensions), so a config-derived legend is exactly right:
  complete for every frame by construction. Verified identical across all 121 frames of sim 38.
- **Unblocks branch 3.** The planned `_filterLegendSVG` (rebuilding `legend.svg` on its 65 px
  pitch after filtering) is unnecessary.
- **Three times more compact** than the nested version: 147 px band → 49 px.
- No automatic `dead` entry. It existed only because scanning saw dead cells; `legend.svg` has no
  such row, and "dead" is a state rather than a cell type. Users wanting one pass explicit entries.

### Design details
- `MontageSpec` carries the legend so every movie frame draws the same one; a five-argument
  constructor preserves the old arity. `legend_svg` is typed `Any` (entries *or* a path).
- `_legendEntries(folders)` unions each folder's `legend.svg` rows, first occurrence winning, so a
  sweep mixing configs still explains every type — verified: 52 dev-project sims define 4 cell
  types, 12 define a 5th (`filler`), and a 64-sim montage lists all five.
- `:auto` prefers the free cells trailing the last row, spanning the run, so the legend costs
  **no space**; else a band below.
- `legend="my.svg"` still nests an external file, placed at natural size and shrunk only to fit.
- Legend geometry derives from ratios, so `_px` rounds it — applied only where that noise arises,
  keeping the no-legend path byte-identical.
- Titles' hardcoded `font-size="22"` became `_TITLE_FONT_SIZE`, in `types.jl` because
  `MontageSpec`'s constructor defaults to it and `types.jl` is included first.

### Bug caught only by looking at the render
The band is sized against the *available* width, but the drawing pass was re-laying-out against the
legend's own *used* width. That puts the final entry exactly on a float equality boundary: for sim
38's 4-entry legend across a 1260 px strip it wrapped onto a second row that the reserved band had
no height for, **clipping `nk` off the bottom edge**. Tests passed — two earlier cases happened to
fall the other side of the boundary. Fixed by carrying the sizing width through to the drawing
pass, with a regression test asserting every legend marker sits inside the figure. Lesson: for
layout code, render and look; exact-dimension assertions can pass while the picture is wrong.

### Also recorded
`identity` vs `nothing` for the `transform` hook coming in branch 3: measured on a real 62 KB
`final.svg`, `identity(s) === s` is `true`, pointers equal, `@allocated` **0 bytes**. Zero-cost
default. (Julia's `replace` likewise returns the same object when nothing matches.)

### Verification
- Core suite **112/112** (was 49), no heavy deps, precompiles with no method-overwrite warnings.
  Includes the byte-identical-when-`legend=nothing` guard, the wrap-not-scale assertion, and a
  check that a drawn legend emits no nested `<svg>`.
- Dev project, rendered with `rsvg-convert` and eyeballed: sim 38 storyboard → one compact centred
  row (`tumor_epi`/`tumor_mes`/`caf`/`nk`) at title size, nothing clipped; 3-sim montage → legend
  wrapped into the free (2,2) cell with **identical dimensions** to no-legend; 64-sim montage →
  `filler` correctly included from the 12 sims that define it; movie legend identical in frames 1
  and 121; folder with no `legend.svg` → no legend.

---

## Session: `tableau` cell selection + colouring (2026-08-05)

Branch `feature/tableau-cell-color` (stacked on `feature/svg-legend`). To-do items 2 ("use
alternate data for coloring cells") and 3 ("filter cell types") for the data-driven verb, plus two
corrections the user caught along the way.

### The feature
Two independent knobs on the focal cell layer: **which cells** (`cell_types`, `include_dead`) and
**what colour means** (`color`, `color_mode`, `cell_colormap`). The interesting part is that
colouring has **two visual modes needing different keys** — a categorical column wants one labelled
series per value plus a Legend (the `cell_type_name` default, i.e. the pre-existing behaviour); a
continuous column wants a single scatter plus a Colorbar. `color_mode` exists because
`current_phase` is stored as `Float64`, so `:auto` reads it as continuous when it is really
discrete. `cell_colormap` is separate from `colormap` (the substrates') so the two scales are
independent.

`_tableauFigure` gained `focal_colorbar_label`: the focal panel is wrapped in the same
`Axis`-plus-`Colorbar` `GridLayout` the satellites already use, reading the plot the focal callback
returns — reusing the documented "each returning the plot its colorbar reads" convention.

### Correction 1 (user): the `legend` API conflated two things
Branch 1 shipped `legend` meaning *either* content *or* placement, with a `legend_file` escape for
the other half. The user spotted the consequence: passing your own entries **and** choosing a
placement was only expressible as `legend=:bottom, legend_file=[…]` — entries inside a kwarg named
"file". Fixed by making the axes orthogonal:

| | before | after |
|---|---|---|
| what to draw | `legend` *or* `legend_file` | `legend` |
| where it goes | `legend` (same kwarg) | `legend_position` |

`legend_file` is gone; `_normalizeLegend` now normalizes content only; `:auto` means "discover from
the run" and is resolved by the extension (`_resolveAuto`) **before** core is called, leaving
`legend_position` free. Net: one fewer kwarg and the natural case is now the obvious spelling.

### Correction 2 (user): tableau should use PhysiCell's own colours
The first version left tableau on Makie's palette, so a montage legend (PhysiCell's
greys/reds/yellows) and a tableau of the same run (Makie's blues/oranges) disagreed. The user's
call — for PhysiCell specifically, carry PhysiCell's colours into tableau — is clearly right, and
branch 1's `legend.svg` parser already produces exactly the needed type→colour map.

Sharing it across extensions required the **core-hook pattern**: `_legendEntries` was promoted to
core-declared `Montage._cellTypeLegend`, implemented in `MontagePhysiCellOutputExt`, now called by
the CairoMakie extension too. Loading is guaranteed — activating a CairoMakie+PhysiCellOutput
extension implies PhysiCellOutput is present. Verified: `tumor_epi` → grey `(0.502,0.502,0.502)`,
`tumor_mes` → red, `caf` → yellow, `nk` → green, matching `legend.svg` exactly.

`_parseSVGColor` handles the `rgb(r,g,b)` form PhysiCell can emit, which Makie cannot parse; named
colours and hex pass through untouched.

### Gotcha: a core hook must not have an identically-signed fallback
First attempt declared the hook as `_cellTypeLegend(folders) = Tuple{String,String}[]` in core. The
extension's `Montage._cellTypeLegend(folders)` then has the **same** signature, making it an
*overwrite*, and Julia errors: *"Method overwriting is not permitted during Module
precompilation."* The existing hooks avoid this by giving the core fallback a deliberately **more
general** signature than the extension's method (`_recordSVGMovie`'s untyped args vs. the ext's
typed ones; `_montage(::MontageBackend)` vs. `_montage(::MakieBackend)`). Since core never calls
this one, the fix is a bare `function _cellTypeLegend end` with no methods at all.

**Worth noting how this was nearly missed:** the core suite passed 112/112 while all three
extensions were failing to precompile, because heavy deps stay out of that suite by design. After
touching a core hook, load the extensions explicitly (`using Montage, PhysiCellOutput, CairoMakie`)
and check for `✓` rather than `?` in the precompile output.

### Two more things real data forced
1. **Filtering silently recoloured the figure.** Makie assigns series colours by plotting order, so
   `caf` was the third series in a full plot but the *first* under `cell_types=["caf","nk"]`. Fixed
   by `_paletteOrder` + `Cycled` — slots come from the config's type list. Now largely subsumed by
   using PhysiCell's colours, but it still covers non-cell-type categorical columns and runs
   without a `legend.svg`.
2. **Positions and colours cannot be separate Observables.** They must stay equal-length, and
   updating them one at a time transiently mismatches — Makie's scatter rejects that. The
   continuous movie path carries `(points, colours)` in **one** Observable with `lift`-derived
   views. Verified across frames where the cell count changes 300 → 511.

### Why the movie colorrange is global, and computed after filtering
Pressure's per-frame ranges over `0:30:120` are `[(0,0), (0,4.17), (0,2.99), (0,3.0), (0,4.06)]` —
frame 1 is **uniformly zero**, so a per-frame scale would render it as a meaningless full-range
spread. Extracted frames 1 and 5 confirm both render correctly on the shared 0–4.17 scale.
Filtering first matters too: unfiltered `(0, 4.171)` vs `tumor_epi` live-only `(0, 3.002)`.

### Also picked up
The `_assertWritable` message improved in `1b416f6` was **untested** — the assertion was only
`occursin("already exists", …)`, which the old bare message also satisfied. Added assertions for
`overwrite=true`, `output=`, and the offending path, so the actionable wording is pinned.

### Verification
- Core suite **112/112**, dependency-free; all three extensions precompile clean.
- Scratch env (Montage-dev + PhysiCellOutput + CairoMakie) against `GeorgetownR01`: filtering counts
  (`all=511`, `["nk","caf"]=200`, `include_dead=false` drops 29, scalar `"nk"=100`); bad type and bad
  column both error helpfully; mode detection for `cell_type_name`/`dead`/`pressure`/`current_phase`;
  six stills and three movies rendered and inspected; resolved colours read off the `Figure` to prove
  PhysiCell colours and filter-stability; legend placement measured (`:top` legend at cy=30.7 with
  panels at 95.4, `:bottom` at 397.7 with panels at 46.0, identical totals, own entries honoured).

---

## Session: cell filtering for `montage` / `storyboard` (2026-08-05)

Branch `feature/svg-cell-filter` (stacked on `feature/tableau-cell-color`). To-do item 3 for the
SVG verbs — Tier 1 of the plan's two-tier split.

### The core seam
Core gains exactly one generic thing and no PhysiCell or colour knowledge:
`Panel(content; title, transform=identity)`, a function `SVG text -> SVG text` applied in
`_svgGrid` just before placement. Per the user's steer, there is **no `colorby`/`cell_types`/
colormap in core** — the seam *is* the "users can edit their own SVGs" affordance, made ergonomic.

Per-`Panel` rather than a verb kwarg, because a montage across simulations needs a different
closure per panel (each bound to that run's data). Filtering happens to be uniform; recolouring
(Tier 2) is not.

For movies, `transform` may be a `Vector` parallel to the frames (`_frameTransform` indexes it), so
a per-timepoint edit is expressible; a single function applies to every frame.

### Filtering needs no data at all
PhysiCell tags every cell — `<g id="cell442" type="tumor_epi" dead="true">` — so `cell_types` and
`include_dead` are just "drop the non-matching groups". Cell groups never nest, so a non-greedy
match to the first `</g>` is exact, and requiring `id="cell…"` scopes the edit to the cells layer
on its own (the `tissue` wrapper and `ECM` group have other ids; the time/agent text is not a `<g>`).

Two details that make the output honest rather than merely filtered:
- **The "N agents" caption is rewritten** to the number actually drawn. A figure captioned
  `511 agents` while showing 200 of them would be wrong, and the count is free — we are already
  visiting every group.
- **The legend narrows to the kept types** (user's call). Worth being precise about why this is not
  in tension with the config-driven legend: entries are deliberately *not* narrowed to what happens
  to be visible in a snapshot (that is what keeps one legend correct across a whole movie), but an
  explicit `cell_types` filter is different — those cells were removed on purpose.

### What Tier 1 no longer needs
The plan budgeted `_filterLegendSVG`, rebuilding PhysiCell's `legend.svg` on its 65 px row pitch
after filtering. Unnecessary: the legend is drawn from `(label, colour)` entries now, so narrowing
it is a one-line `filter`.

### Verification
- Core suite **126/126**, dependency-free. Tests cover the seam itself: `identity` default,
  `_frameTransform` vector indexing, a transform applied while stitching (including one panel
  transformed and its neighbour untouched), explicit `identity` being byte-identical, a transform
  that changes the intrinsic size correctly changing the layout, and per-frame transforms in a movie.
- Real data (sim 1's `final.svg`, 511 cells / 29 dead): `["nk","caf"]` → 200, scalar `"nk"` → 100,
  `include_dead=false` → 482, both → 234; captions track exactly; `tumor_epi` 263 → 234 under
  `include_dead=false`, i.e. all 29 dead cells were tumour epithelium; scale bar, time text and
  `tissue` group preserved; `_cellFilter(nothing, true) === identity`. Filtered storyboards rendered
  and eyeballed — legend correctly shows only the kept two types.

### Also fixed (user)
`legend_font_size`'s default was `_TITLE_FONT_SIZE` in code but written as a literal `22` in three
docstring spots, which would have silently lied if the constant changed. The docstrings now say
`<title size>` (matching the existing `output=<auto: …>` convention) and describe the default rather
than restating it. Same class of duplication: `title_y = y0 + 24` hardcoded a baseline offset
derived from the font size — now `y0 + _TITLE_FONT_SIZE + 2`, which is byte-identical (22+2 == 24)
and no longer drifts if the constant changes. The `_px` docstring's example also still referenced
the font-ratio arithmetic deleted in branch 1; updated.

### Note (visible in the rendered output, not addressed)
With `include_dead=true` (the default) dead cells render **black** with no legend entry, since
`legend.svg` has no dead row and the legend is config-driven. `include_dead=false` removes them, or
an explicit `legend=[…, ("dead","black")]` supplies the key. Left alone deliberately — "dead" is a
state, not a cell type.

---

## Session: colouring cells by data in the SVG verbs — Tier 2 (2026-08-05)

Branch `feature/svg-cell-color` (stacked on `feature/svg-cell-filter`). The last and largest piece
of to-do item 2: `color=:pressure` on `montage`/`storyboard`, not just `tableau`.

### The join is what makes this possible at all
Every cell group carries `id="cell442"`, which joins to the `ID` column of the snapshot's cells
table. So *any* of the ~130 columns can drive the colour of an already-rendered figure. Verified on
sim 1: all 511 ids in the SVG matched a row in the table, no misses.

`_cellTransform` now does filtering **and** recolouring in one pass, since both walk the same cell
groups. Cells with no matching row keep PhysiCell's own colour, with a single warning naming how
many.

### Only `fill` is rewritten
The nucleus circle's `stroke` still carries the old cell-type colour. That looked like a defect
until measured: PhysiCell writes `stroke-width="0.5"` in a 1000 px canvas, which is ~0.15 px once a
panel is scaled to 300 px — invisible. Leaving strokes alone dropped a chunk of fiddly logic (the
outer circle's stroke is `black` and must *stay* black, the nucleus's must not) for no visible cost.

### Colormaps: deliberately a small built-in set
`:viridis`, `:plasma`, `:grays` as 9-anchor RGB ramps with linear interpolation, emitting
`rgb(r,g,b)`. No colour package, no CairoMakie — the entire point of this path is that it stays
light, and a cell dot does not need a 256-entry LUT. An unknown name errors saying exactly that and
pointing at `tableau`, which re-plots through Makie and has the full set. That boundary is the
honest one: two paths with different weights get different capability, and the error explains why.

### The colorbar, and a third legend form in core
Under continuous colouring a cell-type key is worse than nothing — it names colours the figure no
longer uses — so `:auto` becomes a colorbar (`_legendFor`).

Placing it needed a decision. The legend machinery took entries (drawn) or an SVG source (nested);
a colorbar is neither, and nesting one would reintroduce exactly the nested-`<svg>` problem branch 1
removed for editability. Rather than teach core what a colorbar is, core gained a **draw function**
form: `(x, y, avail_w) -> (fragment, w, h)`, called once to measure and once to emit. Core places
and sizes something it knows nothing about; the extension owns the drawing. It also adapts to any
width, so `:auto` can still use a spare grid cell.

The bar itself is **one** gradient-filled `<rect>` plus flat `<text>` — a single object to nudge in
Illustrator rather than the dozens of slices a gradient-free version would need.

### Pooled range, computed after filtering
`_colorPlan` pools the value range over every state of every panel. This is not a nicety: a montage
whose panels each had their own scale would be actively misleading, since the whole point is
comparison. Verified — sim 1 alone ranges 0–4.06; sims 1+2 together 0–5.46, so sim 2's higher
pressures widen the shared bar and one colorbar serves both panels. Filtering is applied first
(`_cellAttributes` re-reads type/dead from the SVG so the range sees exactly the cells that will be
drawn), or excluded cells would stretch the ramp.

### Verification
- Core suite **133/133**, dependency-free — including the new draw-function legend form (measured
  once, emitted once, emitted flat, centred, and usable in a spare cell).
- Real data: ramp values and clamping; unknown-colormap error; 511/511 id join; 8 distinct fills →
  135 after recolouring with type colours gone and non-cell content intact; colorbar geometry, one
  gradient rect, labels; storyboard and cross-simulation montage rendered and eyeballed.

### Notes (not addressed)
- The gradient's element id is fixed (`montage-cbar`). Harmless while there is one legend per
  figure, but two colorbars in one document would collide — worth a unique suffix if that ever
  becomes possible.
- A recoloured figure keeps PhysiCell's own colours for cells with no data value, which mixes two
  colour meanings in one panel. Rare (it needs an id present in the SVG but absent from the table)
  and warned about, but a stricter option could drop those cells instead.
