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
    _svgGrid(panels; ncols, panel_width, title_height, pad) -> String

Build a uniform titled grid of `panels` (row-major) and return the composed SVG as a
string. `ncols` sets the number of columns — `montage` uses `ceil(sqrt(n))` (the default),
`storyboard` uses `n` (a single ordered row). Cells are uniform, sized from the *largest*
intrinsic aspect ratio so nothing overflows or clips.

The title band is reserved for the whole grid only if at least one panel is titled;
an all-untitled composition reserves no band (no wasted vertical space).
"""
function _svgGrid(panels::AbstractVector{Panel};
                  ncols::Integer=ceil(Int, sqrt(length(panels))),
                  panel_width::Real=300, title_height::Real=34, pad::Real=12)
    isempty(panels) && error("a composition requires at least one panel")
    ncols >= 1 || error("ncols must be ≥ 1; got $ncols")

    # read each panel's SVG once; keep text alongside intrinsic dims
    contents = map(panels) do p
        p.content isa AbstractString ||
            error("the :svg backend needs an SVG file path per panel; got $(typeof(p.content))")
        isfile(p.content) || error("SVG file not found: $(p.content)")
        text = read(p.content, String)
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
    total_h = nrows * cell_h + (nrows + 1) * pad

    io = IOBuffer()
    println(io, """<?xml version="1.0" encoding="UTF-8" standalone="no"?>""")
    println(io, """<svg xmlns="http://www.w3.org/2000/svg" width="$total_w" height="$total_h" viewBox="0 0 $total_w $total_h">""")
    println(io, """<rect x="0" y="0" width="$total_w" height="$total_h" fill="white"/>""")

    for (i, (panel, c)) in enumerate(zip(panels, contents))
        row = (i - 1) ÷ ncols
        col = (i - 1) % ncols
        x0 = pad + col * (cell_w + pad)
        y0 = pad + row * (cell_h + pad)

        if !isempty(panel.title)
            title_x = x0 + cell_w / 2
            title_y = y0 + 24
            println(io, """<text x="$title_x" y="$title_y" text-anchor="middle" font-family="Arial" font-size="22" font-weight="bold" fill="black">$(_escapeXML(panel.title))</text>""")
        end

        println(io, _nestedSVG(c.text, x0, y0 + band, panel_width, panel_height))
    end

    println(io, "</svg>")
    return String(take!(io))
end

"""Escape the five XML special characters so titles can't break the SVG."""
function _escapeXML(s::AbstractString)
    s = replace(s, "&" => "&amp;")
    s = replace(s, "<" => "&lt;")
    s = replace(s, ">" => "&gt;")
    s = replace(s, "\"" => "&quot;")
    s = replace(s, "'" => "&apos;")
    return s
end
