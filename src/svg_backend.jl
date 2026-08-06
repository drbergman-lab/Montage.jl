# SVG string-stitch backend — the core default.
#
# Ported from the prototype `StitchFinalSVGs.jl`. Composes existing SVG files into
# a single SVG by inlining each as a nested, positioned <svg> element. Lossless
# vector, exact source styling, no re-rendering, no data access — but static only.

"""
    _svgDimensions(svg_text) -> (width, height)

Extract the intrinsic `(width, height)` (as `Float64`) from an SVG's root `<svg>`
tag. Parsed from the tag — never hardcoded — so any source size works.
"""
function _svgDimensions(svg_text::AbstractString)
    m = match(r"<svg\b.*?>"s, svg_text)
    m === nothing && error("no root <svg> tag found in SVG text")
    open_tag = m.match
    wm = match(r"\bwidth\s*=\s*\"([\d.]+)", open_tag)
    hm = match(r"\bheight\s*=\s*\"([\d.]+)", open_tag)
    (wm === nothing || hm === nothing) &&
        error("root <svg> tag is missing a numeric width/height attribute")
    return parse(Float64, wm.captures[1]), parse(Float64, hm.captures[1])
end

"""
    _nestedSVG(svg_text, x, y, w, h) -> String

Return a self-contained, positioned copy of `svg_text` as a nested `<svg>` element.
The child is placed at `(x, y)` in a `w × h` box and scaled — via a `viewBox` set to
its intrinsic size plus `preserveAspectRatio="xMidYMid meet"` — to fit while keeping
its aspect ratio. The `viewBox` is what makes the child *scale* instead of *clip*.
"""
function _nestedSVG(svg_text::AbstractString, x, y, w, h)
    iw, ih = _svgDimensions(svg_text)
    body = replace(svg_text, r"<\?xml.*?\?>"s => "")          # drop XML declaration
    body = replace(body, r"<svg\b.*?>"s => ""; count=1)        # drop original root <svg ...>
    body = replace(body, r"</svg>\s*$"s => "")                 # drop its closing tag
    return """
    <svg x="$x" y="$y" width="$w" height="$h" viewBox="0 0 $iw $ih" preserveAspectRatio="xMidYMid meet" xmlns="http://www.w3.org/2000/svg">
    $body
    </svg>"""
end

"""
    _svgSource(src) -> String

Read `src` as SVG text: a path to an SVG file, or already-SVG text (detected by a leading
`<`). Used by the *external* legend escape hatch (`legend="my_legend.svg"`), which nests the
file as-is; the built-in legend is drawn from entries instead — see [`_legendLayout`](@ref).
"""
function _svgSource(src::AbstractString)
    occursin(r"^\s*<", src) && return String(src)
    isfile(src) || error("SVG file not found: $src")
    return read(src, String)
end

"""
    _legendLayout(entries, avail_w; font_size) -> (placed, w, h, r, gap)

Flow-lay `entries` — `(label, color)` pairs — left to right at `font_size`, wrapping to a new
row when the next entry would exceed `avail_w`. Returns the placed items (relative to the
legend's own origin), the used size, the marker radius and the marker→label gap.

Because the legend is *drawn* rather than scaled from a source image, it is authored at the
composition's title size and simply wraps to fit whatever space it is given. That is what makes
the placement rules simple: there is no scale factor and no minimum-legibility problem.

Text width is estimated at `0.58 · font_size` per character (about right for Arial); the result
only affects wrapping and the reported width, so a small error is harmless.
"""
function _legendLayout(entries, avail_w::Real; font_size::Real)
    r = 0.45 * font_size                       # marker radius
    gap = 0.4 * font_size                      # marker -> label
    item_gap = 1.2 * font_size                 # entry -> entry
    row_h = 1.7 * font_size
    placed = Tuple{Float64,Float64,String,String}[]   # (x, row-centre y, label, color)
    x = 0.0; row = 0; used_w = 0.0
    for (label, color) in entries
        w = 2r + gap + 0.58 * font_size * length(label)
        if x > 0 && x + w > avail_w             # wrap (never on the first entry of a row)
            used_w = max(used_w, x - item_gap)
            row += 1
            x = 0.0
        end
        push!(placed, (x, row * row_h + row_h / 2, String(label), String(color)))
        x += w + item_gap
    end
    used_w = max(used_w, x - item_gap)
    return placed, used_w, (row + 1) * row_h, r, gap
end

"""
    _svgLegend(entries, x0, y0, avail_w; font_size) -> (fragment, w, h)

Draw `entries` as a legend at `(x0, y0)`, laid out by [`_legendLayout`](@ref).

Emits **flat, top-level `<circle>` and `<text>` elements** — deliberately not a nested `<svg>`.
Nested SVGs are the thing PowerPoint and Illustrator handle worst, and being able to open the
composition in those tools and nudge the legend is a large part of why the output is SVG.
"""
function _svgLegend(entries, x0::Real, y0::Real, avail_w::Real; font_size::Real)
    placed, w, h, r, gap = _legendLayout(entries, avail_w; font_size)
    io = IOBuffer()
    for (x, yc, label, color) in placed
        cx, cy = x0 + x + r, y0 + yc
        println(io, """<circle cx="$(_px(cx))" cy="$(_px(cy))" r="$(_px(r))" stroke="black" stroke-width="1" fill="$(_escapeXML(color))"/>""")
        println(io, """<text x="$(_px(cx + r + gap))" y="$(_px(cy + 0.35 * font_size))" font-family="Arial" font-size="$(_px(font_size))" fill="black">$(_escapeXML(label))</text>""")
    end
    return String(take!(io)), w, h
end

"""
    _normalizeLegend(legend) -> legend_or_nothing

Normalize the `legend` keyword, which says **what** to draw. Where it goes is the separate
`legend_position` keyword — the two are orthogonal, so any content can take any placement.

| `legend` | result |
|---|---|
| `nothing` / `false` | `nothing` — no legend |
| a vector of `(label, color)` entries | the entries, drawn (empty ⇒ no legend) |
| a function `(x, y, avail_w) -> (fragment, w, h)` | called to draw it |
| a path or SVG string | the source, nested as-is |
| `:auto` | `nothing` in the core — it means "discover from the data source", which only the PhysiCell extensions can do; they resolve it to entries before calling in |
"""
function _normalizeLegend(legend)
    (legend === nothing || legend === false || legend === :auto) && return nothing
    legend isa Function && return legend
    legend isa AbstractString && return String(legend)
    legend isa AbstractVector && return isempty(legend) ? nothing : legend
    error("unrecognized legend $(repr(legend)); expected nothing, `(label, color)` entries, an " *
          "SVG path, or :auto. To place the legend, use `legend_position` " *
          "(:auto, :bottom, :top, or a (row, col) cell)")
end

"""
    _cellTypeLegend(folders) -> Vector{Tuple{String,String}}

Core-declared hook: the `(label, colour)` entries describing the cell types in one or more
simulation output folders. Implemented by `MontagePhysiCellOutputExt`, which owns the
PhysiCellOutput weakdep and knows the output-folder layout.

Declared here, rather than privately in that extension, so the CairoMakie extensions can reach it
too — `tableau` uses it to colour cells with **PhysiCell's own** colours, so a `tableau` and a
`montage`/`storyboard` of the same run agree. Extensions cannot `using` one another, so a
core-owned hook is the supported way to share this.

**Declared with no methods on purpose.** Core never calls it, and every caller is an extension
that necessarily loads `MontagePhysiCellOutputExt` alongside itself (activating a
CairoMakie+PhysiCellOutput extension implies PhysiCellOutput is present). Giving it an untyped
fallback here instead would make the extension's identically-signed method an *overwrite* rather
than an addition, which Julia rejects during precompilation — the reason `_recordSVGMovie` and
`_montage` take a deliberately more general fallback signature than their extension methods.
"""
function _cellTypeLegend end

"""
    _svgGrid(panels; ncols, panel_width, title_height, pad,
             legend_svg, legend_position, legend_font_size) -> String

Build a uniform titled grid of `panels` (row-major) and return the composed SVG as a
string. `ncols` sets the number of columns — `montage` uses `ceil(sqrt(n))` (the default),
`storyboard` uses `n` (a single ordered row). Cells are uniform, sized from the *largest*
intrinsic aspect ratio so nothing overflows or clips.

The title band is reserved for the whole grid only if at least one panel is titled;
an all-untitled composition reserves no band (no wasted vertical space).

`legend_svg` (from [`_normalizeLegend`](@ref)) adds a legend, in one of three forms:

- a vector of `(label, color)` **entries**, drawn at `legend_font_size` as flat circles and text
  (see [`_svgLegend`](@ref));
- a **draw function** `(x, y, avail_w) -> (fragment, w, h)`, for a legend this module does not know
  how to build — the PhysiCell extension supplies a colorbar this way. Called once to measure and
  once to emit, so it must be pure;
- a **path or SVG string**, nested and scaled to fit.

Placed per `legend_position`:

- `:auto` — the free cells trailing the last row, costing no space at all, else a full-width band
  below. A drawn legend wraps to whatever width it gets, so the run is always usable; a nested
  source SVG has to shrink, so it takes the run only if that is wide enough to stay legible.
- `:bottom` / `:top` — a full-width band at that edge;
- `(row, col)` or `(row, col, span)` — those explicit cells, growing the grid if the row is past
  the last one.

With `legend_svg === nothing` the output is byte-identical to a grid built without any legend
support at all.
"""
function _svgGrid(panels::AbstractVector{Panel};
                  ncols::Integer=ceil(Int, sqrt(length(panels))),
                  panel_width::Real=300, title_height::Real=34, pad::Real=12,
                  legend_svg=nothing, legend_position=:auto,
                  legend_font_size::Real=_TITLE_FONT_SIZE)
    isempty(panels) && error("a composition requires at least one panel")
    ncols >= 1 || error("ncols must be ≥ 1; got $ncols")

    # read each panel's SVG once; keep text alongside intrinsic dims
    contents = map(panels) do p
        p.content isa AbstractString ||
            error("the :svg backend needs an SVG file path per panel; got $(typeof(p.content))")
        isfile(p.content) || error("SVG file not found: $(p.content)")
        p.transform isa AbstractVector && error(
            "this panel's transform is a Vector of $(length(p.transform)) functions, which is the " *
            "per-frame form for a movie panel; a still panel takes a single function")
        # `transform` edits the panel's contents before placement; `identity` is a no-op that
        # returns the same object, so an untransformed grid is byte-identical.
        text = p.transform(read(p.content, String))
        (; text, dims=_svgDimensions(text))
    end

    n = length(panels)
    nrows = ceil(Int, n / ncols)

    band = any(!isempty(p.title) for p in panels) ? Float64(title_height) : 0.0
    aspect = maximum(c.dims[2] / c.dims[1] for c in contents)   # max ih/iw
    panel_height = panel_width * aspect
    cell_w = Float64(panel_width)
    cell_h = band + panel_height

    total_w = ncols * cell_w + (ncols + 1) * pad

    # Resolve the legend before the totals, since a cell placement can grow the grid and a
    # band adds a row of its own. `legend_svg === nothing` skips all of this, leaving the
    # geometry below exactly as it was before legends existed.
    # Three legend kinds: drawn entries, a caller-supplied draw function, or a source SVG to nest.
    # The first two adapt to whatever width they are given; only a nested SVG has to be scaled.
    drawn = legend_svg isa AbstractVector
    custom = legend_svg isa Function
    ltext = (legend_svg === nothing || drawn || custom) ? nothing : _svgSource(legend_svg)
    liw, lih = ltext === nothing ? (0.0, 0.0) : _svgDimensions(ltext)
    legend_cell = nothing               # (row, col, span) when the legend takes grid cells
    legend_band = nothing               # :bottom | :top when it takes a full-width band
    if legend_svg !== nothing
        place = legend_position
        if place === :auto
            # Prefer the free cells trailing the last row — they cost no space. A drawn legend
            # just wraps to whatever width it gets, so this is always safe; a nested source SVG
            # would have to shrink, so only take the run if it is wide enough to stay legible.
            filled = n - (nrows - 1) * ncols          # panels in the last row
            span = ncols - filled                    # free cells after them
            run_w = span * cell_w + (span - 1) * pad
            # Can the legend live in that run of free cells? Entries wrap, so always. A draw
            # function reports its own size, so ask it — it may not be able to shrink far enough
            # (a colorbar's tick labels have a floor), and overflowing into a panel is worse than
            # spending a band. A nested SVG can only scale, so require it not shrink too far.
            fits = span < 1 ? false :
                   drawn    ? true :
                   custom   ? legend_svg(0.0, 0.0, Float64(run_w))[2] <= run_w :
                              run_w / liw >= 0.7
            place = fits ? (nrows, filled + 1, span) : :bottom
        end
        if place isa Tuple
            r, c = Int(place[1]), Int(place[2])
            span = length(place) >= 3 ? Int(place[3]) : 1
            (r >= 1 && 1 <= c <= ncols) ||
                error("legend cell $((r, c)) is outside a grid with $ncols column(s)")
            (r - 1) * ncols + c <= n && @warn "legend cell $((r, c)) overlaps a panel"
            legend_cell = (r, c, min(span, ncols - c + 1))
            nrows = max(nrows, r)       # an explicit row past the last one grows the grid
        elseif place === :bottom || place === :top
            legend_band = place
        else
            error("unrecognized legend position $(repr(place)); expected :auto, :bottom, " *
                  ":top, or a (row, col) grid cell")
        end
    end

    # Size the legend to the space it will occupy: a drawn legend wraps to that width, a nested
    # source SVG scales down to fit it.
    # An external legend is placed at its natural size, only ever shrunk to fit (never blown up).
    legendSize(avail_w, avail_h) =
        drawn  ? (t = _legendLayout(legend_svg, avail_w; font_size=legend_font_size);
                  (_px(t[2]), _px(t[3]))) :
        custom ? (r = legend_svg(0.0, 0.0, Float64(avail_w)); (_px(r[2]), _px(r[3]))) :
                 (s = min(avail_w / liw, avail_h / lih, 1.0); (_px(liw * s), _px(lih * s)))

    grid_h = nrows * cell_h + (nrows + 1) * pad
    total_h = grid_h
    legend_box = nothing                # (x, y, w, h) of the placed legend
    legend_avail = 0.0                  # width the legend was *sized against* (see below)
    y_shift = 0.0                       # panels shift down under a :top band
    if legend_cell !== nothing
        r, c, span = legend_cell
        x0 = pad + (c - 1) * (cell_w + pad)
        y0 = pad + (r - 1) * (cell_h + pad)
        run_w = span * cell_w + (span - 1) * pad     # the legend may span several free cells
        legend_avail = Float64(run_w)
        lw, lh = legendSize(run_w, cell_h)
        legend_box = (_px(x0 + (run_w - lw) / 2), _px(y0 + (cell_h - lh) / 2), lw, lh)
    elseif legend_band !== nothing
        legend_avail = Float64(total_w - 2 * pad)
        lw, lh = legendSize(legend_avail, Inf)
        total_h = _px(grid_h + lh + pad)
        if legend_band === :bottom
            legend_box = (_px((total_w - lw) / 2), grid_h, lw, lh)
        else
            legend_box = (_px((total_w - lw) / 2), Float64(pad), lw, lh)
            y_shift = lh + pad
        end
    end

    io = IOBuffer()
    println(io, """<?xml version="1.0" encoding="UTF-8" standalone="no"?>""")
    println(io, """<svg xmlns="http://www.w3.org/2000/svg" width="$total_w" height="$total_h" viewBox="0 0 $total_w $total_h">""")
    println(io, """<rect x="0" y="0" width="$total_w" height="$total_h" fill="white"/>""")

    for (i, (panel, c)) in enumerate(zip(panels, contents))
        row = (i - 1) ÷ ncols
        col = (i - 1) % ncols
        x0 = pad + col * (cell_w + pad)
        y0 = pad + row * (cell_h + pad) + y_shift

        if !isempty(panel.title)
            title_x = x0 + cell_w / 2
            title_y = y0 + _TITLE_FONT_SIZE + 2      # baseline sits just under the band top
            println(io, """<text x="$title_x" y="$title_y" text-anchor="middle" font-family="Arial" font-size="$(_TITLE_FONT_SIZE)" font-weight="bold" fill="black">$(_escapeXML(panel.title))</text>""")
        end

        println(io, _nestedSVG(c.text, x0, y0 + band, panel_width, panel_height))
    end

    if legend_box !== nothing
        lx, ly, lw, lh = legend_box
        # Drawn legends emit flat circles/text (editable in Illustrator/PowerPoint); an external
        # legend SVG is nested, since we can only place it as an opaque block.
        #
        # Lay out against `legend_avail` — the width the legend was *sized* against — not `lw`,
        # its used width. Re-wrapping at exactly its own width puts the last entry on a float
        # equality boundary, which can wrap it onto a row the reserved band has no height for.
        println(io,
            drawn  ? first(_svgLegend(legend_svg, lx, ly, legend_avail; font_size=legend_font_size)) :
            custom ? first(legend_svg(lx, ly, legend_avail)) :
                     _nestedSVG(ltext, lx, ly, lw, lh))
    end

    println(io, "</svg>")
    return String(take!(io))
end

"""
    _px(x) -> Float64

Round a coordinate for emission. Legend geometry is built from fractions of the font size
(`0.45 · font_size` for a marker radius, and so on), so it picks up float noise that would
otherwise land verbatim in the SVG. Applied only where that noise arises, so the no-legend path
stays byte-identical.
"""
_px(x) = round(Float64(x); digits=4)

"""
    _slotRC(slot, ncols) -> (row, col)

Row-major 1-based grid slot → `(row, col)`. Used to find the first free cell after the last
panel, which is where an `:auto` legend goes when the layout has a spare.
"""
_slotRC(slot::Integer, ncols::Integer) = ((slot - 1) ÷ ncols + 1, (slot - 1) % ncols + 1)

"""Escape the five XML special characters so titles can't break the SVG."""
function _escapeXML(s::AbstractString)
    s = replace(s, "&" => "&amp;")
    s = replace(s, "<" => "&lt;")
    s = replace(s, ">" => "&gt;")
    s = replace(s, "\"" => "&quot;")
    s = replace(s, "'" => "&apos;")
    return s
end
