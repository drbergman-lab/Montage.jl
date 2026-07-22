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
