using Montage
using Test

# Tiny hand-written SVGs of differing intrinsic sizes to exercise the max-aspect
# grid logic — no PCMM, no CairoMakie, no external fixtures.
const SVG_SQUARE = """<?xml version="1.0"?>
<svg width="100" height="100" xmlns="http://www.w3.org/2000/svg"><rect width="100" height="100" fill="red"/></svg>"""
const SVG_TALL = """<svg width="100" height="200" xmlns="http://www.w3.org/2000/svg"><rect width="100" height="200" fill="blue"/></svg>"""

# An external legend SVG (the `legend="my.svg"` escape hatch): placed at its natural 400×80,
# shrunk only if it will not fit.
const SVG_LEGEND = """<svg width="400" height="80" xmlns="http://www.w3.org/2000/svg"><circle cx="20" cy="40" r="15" fill="grey"/><text x="50" y="52" font-family="Arial" font-size="40" fill="black">type A</text></svg>"""
# PhysiCell's real legend.svg proportions: too wide for one 300px cell, so an external legend of
# these proportions must fall back to a band rather than shrink to ~0.21.
const SVG_LEGEND_WIDE = """<svg width="1440" height="260" xmlns="http://www.w3.org/2000/svg"><circle cx="32.5" cy="32.5" r="25" fill="grey"/><text x="72.5" y="45.25" font-family="Arial" font-size="42.5" fill="black">tumor_epi</text></svg>"""

"""Write the given SVG texts to temp files, run `f(paths)`, and clean up."""
function withtmpsvgs(f, texts...)
    dir = mktempdir()
    paths = String[]
    for (i, t) in enumerate(texts)
        p = joinpath(dir, "panel$i.svg")
        write(p, t)
        push!(paths, p)
    end
    try
        f(paths)
    finally
        rm(dir; recursive=true, force=true)
    end
end

@testset "Montage.jl" begin

    @testset "SVG helpers" begin
        @test Montage._svgDimensions(SVG_SQUARE) == (100.0, 100.0)
        @test Montage._svgDimensions(SVG_TALL) == (100.0, 200.0)
        nested = Montage._nestedSVG(SVG_SQUARE, 5, 10, 300, 300)
        @test occursin("viewBox=\"0 0 100.0 100.0\"", nested)
        @test occursin("preserveAspectRatio=\"xMidYMid meet\"", nested)
        @test occursin("x=\"5\"", nested)
        # child XML declaration and original root tag are stripped
        @test !occursin("<?xml", nested)
        @test count("<svg", nested) == 1
        @test_throws Exception Montage._svgDimensions("<not-svg/>")
    end

    @testset "Panel + loose normalization" begin
        @test Panel("a.svg").title == ""
        @test Panel("a.svg"; title="A").title == "A"
        @test Panel("a.svg", "A").title == "A"
        ps = Montage._asPanels(["a.svg", Panel("b.svg"; title="B")])
        @test length(ps) == 2
        @test all(p -> p isa Panel, ps)
        @test ps[1].title == "" && ps[2].title == "B"
    end

    @testset "montage :svg — titled grid" begin
        withtmpsvgs(SVG_SQUARE, SVG_TALL, SVG_SQUARE) do paths
            panels = [Panel(paths[1]; title="A"), Panel(paths[2]; title="B"), Panel(paths[3]; title="C")]
            svg = montage(panels; panel_width=300, title_height=34, pad=12, output=nothing)
            # every title present, correctly escaped where needed
            @test occursin(">A<", svg) && occursin(">B<", svg) && occursin(">C<", svg)
            # one nested child <svg> per panel + the root
            @test count("<svg", svg) == 4
            # n=3 -> ncols=2, nrows=2; band reserved (34) because titles exist;
            # max aspect = 200/100 = 2 -> panel_height = 600, cell_h = 634
            # total_w = 2*300 + 3*12 = 636 ; total_h = 2*634 + 3*12 = 1304
            @test occursin("width=\"636.0\"", svg)
            @test occursin("height=\"1304.0\"", svg)
        end
    end

    @testset "montage :svg — untitled reserves no band" begin
        withtmpsvgs(SVG_SQUARE, SVG_SQUARE) do paths
            svg = montage(paths; panel_width=300, title_height=34, pad=12, output=nothing)  # loose, untitled
            @test !occursin("<text", svg)
            # n=2 -> ncols=2, nrows=1; no band; aspect=1 -> panel_height=300, cell_h=300
            # total_h = 1*300 + 2*12 = 324
            @test occursin("height=\"324.0\"", svg)
        end
    end

    @testset "title XML-escaping" begin
        withtmpsvgs(SVG_SQUARE) do paths
            svg = montage([Panel(paths[1]; title="a & b <c>")]; output=nothing)
            @test occursin("a &amp; b &lt;c&gt;", svg)
        end
    end

    @testset "output writing + overwrite guard" begin
        withtmpsvgs(SVG_SQUARE) do paths
            # explicit path writes, and returns the same SVG it wrote
            out = joinpath(mktempdir(), "sub", "grid.svg")
            ret = montage(paths; output=out)
            @test isfile(out) && read(out, String) == ret
            # re-writing an existing file errors unless overwrite=true
            @test_throws ErrorException montage(paths; output=out)
            @test montage(paths; output=out, overwrite=true) == ret
            # output=nothing returns the string without writing
            @test montage(paths; output=nothing) isa String
            # writes by default to ./montage.svg in the current directory
            cd(mktempdir()) do
                montage(paths)
                @test isfile("montage.svg")
                @test_throws ErrorException montage(paths)          # guard applies to the default too
            end
        end
    end

    @testset "backend selection + errors" begin
        withtmpsvgs(SVG_SQUARE) do paths
            @test_throws ErrorException montage(paths; backend=:makie)   # ext not loaded
            @test_throws ErrorException montage(paths; backend=:bogus)   # unknown backend
        end
        @test_throws ErrorException montage(Panel[])                     # empty
    end

    @testset "montage movie spec" begin
        withtmpsvgs(SVG_SQUARE, SVG_TALL, SVG_SQUARE, SVG_TALL) do paths
            # animated panels + output=nothing -> a MontageSpec (no rendering, no heavy deps)
            spec = montage([Panel([paths[1], paths[2]]; title="A"),
                            Panel([paths[3], paths[4]]; title="B")]; output=nothing)
            @test spec isa MontageSpec
            @test spec.nframes == 2
            @test length(spec.panels) == 2
            # per-frame SVG reuses the static stitcher: root + one child per panel
            f1 = Montage._svgFrame(spec, 1)
            @test occursin(">A<", f1) && occursin(">B<", f1)
            @test count("<svg", f1) == 3
            @test_throws BoundsError Montage._svgFrame(spec, 3)
            # one-call movie (output=path) routes to record → errors without the movie ext
            @test_throws ErrorException montage([Panel([paths[1], paths[2]])]; output=joinpath(mktempdir(), "m.mp4"))
            # record directly, without the movie extension loaded -> helpful error
            @test_throws ErrorException record(spec, joinpath(mktempdir(), "x.mp4"))
            # record's non-clobber guard fires (before the extension check) on an existing path
            existing = joinpath(mktempdir(), "there.mp4"); touch(existing)
            guard_err = try; record(spec, existing); catch e; sprint(showerror, e); end
            @test occursin("already exists", guard_err)
            # the message must stay *actionable* — it names both ways out. Asserting only
            # "already exists" would pass for a bare message too, leaving the hint unpinned.
            @test occursin("overwrite=true", guard_err)
            @test occursin("output=", guard_err)
            @test occursin(existing, guard_err)              # and says which path
        end
    end

    @testset "montage movie — index truncation + warning" begin
        withtmpsvgs(SVG_SQUARE, SVG_SQUARE, SVG_SQUARE) do paths
            local spec
            @test_logs (:warn,) match_mode=:any begin
                spec = montage([Panel([paths[1], paths[2]]),   # 2 frames
                                Panel([paths[3]])]; output=nothing)   # 1 frame
            end
            @test spec.nframes == 1                             # truncated to shortest
        end
        # all panels a single image -> still image (SVG string)
        withtmpsvgs(SVG_SQUARE, SVG_SQUARE) do paths
            @test montage([Panel(paths[1]), Panel(paths[2])]; output=nothing) isa String
        end
    end

    @testset "storyboard — ordered single-row strip" begin
        withtmpsvgs(SVG_SQUARE, SVG_SQUARE, SVG_SQUARE) do paths
            svg = storyboard([Panel(paths[1]; title="t0"), Panel(paths[2]; title="t1"),
                              Panel(paths[3]; title="t2")]; output=nothing)
            @test count("<svg", svg) == 4                       # root + 3 panels
            # titles appear in time order (reading order preserved)
            @test first(findfirst("t0", svg)) < first(findfirst("t1", svg)) < first(findfirst("t2", svg))
            # single row (ncols=3), titled band 34: total_w=3*300+4*12=948, total_h=334+24=358
            @test occursin("width=\"948.0\"", svg) && occursin("height=\"358.0\"", svg)
        end
    end

    @testset "storyboard — ncols wraps; animated rejected" begin
        withtmpsvgs(SVG_SQUARE, SVG_SQUARE, SVG_SQUARE, SVG_SQUARE) do paths
            svg = storyboard(paths; ncols=2, output=nothing)    # 4 untitled -> 2×2, no band
            @test occursin("width=\"636.0\"", svg) && occursin("height=\"636.0\"", svg)
            # a frame-sequence panel is rejected (storyboard is static)
            @test_throws ErrorException storyboard([Panel([paths[1], paths[2]])]; output=nothing)
        end
    end

    @testset "storyboard — writes by default + guard" begin
        withtmpsvgs(SVG_SQUARE) do paths
            cd(mktempdir()) do
                storyboard(paths)
                @test isfile("storyboard.svg")
                @test_throws ErrorException storyboard(paths)   # overwrite guard
            end
        end
    end

    @testset "Panel transform — the content-editing seam" begin
        @test Panel("a.svg").transform === identity
        @test Panel("a.svg", "A").transform === identity
        f = s -> s
        @test Panel("a.svg"; transform=f).transform === f
        # identity really is free: same object back, no copy (so output stays byte-identical)
        big = SVG_SQUARE^50
        @test identity(big) === big
        # a Vector of transforms is indexed per frame; anything else applies to every frame
        g = s -> s * "!"
        @test Montage._frameTransform([f, g], 2) === g
        @test Montage._frameTransform(f, 7) === f
    end

    @testset "Panel transform — per-frame form rejected on a still panel" begin
        withtmpsvgs(SVG_SQUARE) do paths
            # a Vector is the movie form; on a still panel it used to surface as a bare
            # "Vector is not callable" MethodError
            err = try
                montage([Panel(paths[1]; transform = [identity, identity])]; output=nothing)
            catch e
                sprint(showerror, e)
            end
            @test occursin("Vector of 2 functions", err)
            @test occursin("movie panel", err)
            @test occursin("single function", err)
        end
    end

    @testset "Panel transform — applied when stitching" begin
        withtmpsvgs(SVG_SQUARE, SVG_SQUARE) do paths
            plain = montage(paths; output=nothing)
            # recolour one panel's contents without touching the file on disk
            tinted = montage([Panel(paths[1]; transform = s -> replace(s, "red" => "lime")),
                              Panel(paths[2])]; output=nothing)
            @test occursin("fill=\"lime\"", tinted)
            @test occursin("fill=\"red\"", tinted)              # the untransformed panel is intact
            @test count("fill=\"lime\"", tinted) == 1
            # explicit identity is byte-identical to no transform at all
            @test montage([Panel(paths[1]; transform=identity), Panel(paths[2])]; output=nothing) == plain
            # a transform that changes the intrinsic size changes the layout, as it must
            grown = montage([Panel(paths[1]; transform = s -> replace(s, "height=\"100\"" => "height=\"200\"")),
                             Panel(paths[2])]; output=nothing)
            @test occursin("height=\"624.0\"", grown)           # aspect now 2 -> 600 + 2*12
        end
    end

    @testset "Panel transform — per-frame in a movie" begin
        withtmpsvgs(SVG_SQUARE, SVG_SQUARE) do paths
            # one transform per frame: frame 1 tinted lime, frame 2 tinted blue
            spec = montage([Panel([paths[1], paths[2]];
                                  transform = [s -> replace(s, "red" => "lime"),
                                               s -> replace(s, "red" => "blue")])]; output=nothing)
            @test occursin("fill=\"lime\"", Montage._svgFrame(spec, 1))
            @test occursin("fill=\"blue\"", Montage._svgFrame(spec, 2))
            # a single function applies to every frame
            spec2 = montage([Panel([paths[1], paths[2]];
                                   transform = s -> replace(s, "red" => "teal"))]; output=nothing)
            @test all(occursin("fill=\"teal\"", Montage._svgFrame(spec2, t)) for t in 1:spec2.nframes)
        end
    end

    @testset "legend — helpers" begin
        # SVG text passes through; a path is read
        @test Montage._svgSource(SVG_LEGEND) == SVG_LEGEND
        withtmpsvgs(SVG_LEGEND) do paths
            @test Montage._svgSource(paths[1]) == SVG_LEGEND
        end
        @test_throws ErrorException Montage._svgSource("no/such/file.svg")
        # row-major slot -> (row, col)
        @test Montage._slotRC(4, 2) == (2, 2)
        @test Montage._slotRC(1, 3) == (1, 1)
        @test Montage._slotRC(5, 3) == (2, 2)
    end

    @testset "legend — _normalizeLegend says only *what*" begin
        # content only; placement is the orthogonal `legend_position`
        @test Montage._normalizeLegend(nothing) === nothing
        @test Montage._normalizeLegend(false) === nothing
        @test Montage._normalizeLegend("a.svg") == "a.svg"
        ents = [("a", "red")]
        @test Montage._normalizeLegend(ents) == ents
        @test Montage._normalizeLegend(Tuple{String,String}[]) === nothing   # empty ⇒ none
        # :auto means "discover", which only the PhysiCell extensions can do
        @test Montage._normalizeLegend(:auto) === nothing
        # a placement passed as content is a mistake, and the error points at legend_position
        err = try; Montage._normalizeLegend(:bottom); catch e; sprint(showerror, e); end
        @test occursin("legend_position", err)
        @test_throws ErrorException Montage._normalizeLegend(:sideways)
    end

    @testset "legend — drawn entries" begin
        entries = [("tumor_epi", "grey"), ("caf", "yellow")]
        frag, w, h = Montage._svgLegend(entries, 0, 0, 1000; font_size=22)
        # flat top-level circle/text elements, NOT a nested <svg> (editable in Illustrator)
        @test occursin("<circle", frag) && occursin("<text", frag)
        @test !occursin("<svg", frag)
        @test occursin(">tumor_epi<", frag) && occursin(">caf<", frag)
        @test occursin("fill=\"grey\"", frag) && occursin("fill=\"yellow\"", frag)
        @test occursin("font-size=\"22.0\"", frag)          # authored at the title size
        # wraps rather than scaling when the space is narrow: taller, narrower, same font
        _, w2, h2 = Montage._svgLegend(entries, 0, 0, 120; font_size=22)
        @test h2 > h && w2 < w
        @test occursin("font-size=\"22.0\"",
                       first(Montage._svgLegend(entries, 0, 0, 120; font_size=22)))
        # labels are XML-escaped
        @test occursin("a &amp; b", first(Montage._svgLegend([("a & b", "red")], 0, 0, 999; font_size=22)))
    end

    @testset "legend — drawn legend costs no space" begin
        withtmpsvgs(SVG_SQUARE, SVG_TALL, SVG_SQUARE) do paths
            panels = [Panel(paths[1]; title="A"), Panel(paths[2]; title="B"), Panel(paths[3]; title="C")]
            entries = [("tumor_epi", "grey"), ("caf", "yellow")]
            plain = montage(panels; output=nothing)
            with = montage(panels; legend=entries, output=nothing)
            # wraps into the free (2,2) cell, so the figure does not grow at all
            @test occursin("width=\"636.0\"", with) && occursin("height=\"1304.0\"", with)
            @test occursin("width=\"636.0\"", plain) && occursin("height=\"1304.0\"", plain)
            @test occursin(">tumor_epi<", with) && occursin(">caf<", with)
            @test count("<svg", with) == count("<svg", plain)   # no nested <svg> for the legend
            # an empty entry list is the same as no legend
            @test montage(panels; legend=Tuple{String,String}[], output=nothing) == plain
        end
    end

    @testset "legend — drawn band under a storyboard" begin
        withtmpsvgs(SVG_SQUARE, SVG_SQUARE, SVG_SQUARE) do paths
            entries = [("tumor_epi", "grey"), ("caf", "yellow"), ("nk", "green")]
            svg = storyboard(paths; legend=entries, output=nothing)
            # single row has no free cell, so :auto bands below: grid_h 324 + one 37.4 row + 12
            @test occursin("width=\"948.0\"", svg)
            @test occursin("height=\"373.4\"", svg)
            @test occursin(">nk<", svg)
            @test storyboard(paths; legend=entries, legend_position=:bottom, output=nothing) == svg
        end
    end

    @testset "legend — drawn rows stay inside the reserved band" begin
        # Regression: the band is sized against the available width, but the legend used to be
        # re-laid-out against its own *used* width when drawn — putting the last entry on a float
        # equality boundary, wrapping it onto a row the band had no height for, and clipping it.
        # Four real cell-type labels across a 4-panel strip is the case that caught it.
        withtmpsvgs(fill(SVG_SQUARE, 4)...) do paths
            entries = [("tumor_epi", "grey"), ("tumor_mes", "red"), ("caf", "yellow"), ("nk", "green")]
            svg = storyboard(paths; legend=entries, output=nothing)
            total_h = parse(Float64, match(r"<svg[^>]*height=\"([\d.]+)\"", svg).captures[1])
            # every legend marker must sit wholly inside the figure
            circles = [(parse(Float64, m.captures[1]), parse(Float64, m.captures[2]))
                       for m in eachmatch(r"<circle cx=\"[\d.]+\" cy=\"([\d.]+)\" r=\"([\d.]+)\"", svg)]
            @test !isempty(circles)
            @test all(cy + r <= total_h for (cy, r) in circles)
            # and all four labels are present
            @test all(occursin(">$(e[1])<", svg) for e in entries)
        end
    end

    @testset "legend — no legend is byte-identical" begin
        withtmpsvgs(SVG_SQUARE, SVG_SQUARE) do paths
            base = montage(paths; output=nothing)
            @test montage(paths; legend=nothing, output=nothing) == base
            @test montage(paths; legend=false, output=nothing) == base
            @test montage(paths; legend=:auto, output=nothing) == base   # nothing to discover
        end
    end

    @testset "legend — external SVG is nested at natural size" begin
        withtmpsvgs(SVG_SQUARE, SVG_SQUARE, SVG_SQUARE) do paths
            # 400×80 fits the 924px band, so it is placed unscaled and centred
            svg = storyboard(paths; legend=SVG_LEGEND, output=nothing)
            @test occursin("x=\"274.0\" y=\"324.0\" width=\"400.0\" height=\"80.0\"", svg)
            @test occursin("height=\"416.0\"", svg)          # 324 + 80 + 12
            @test count("<svg", svg) == 5                      # nested, unlike a drawn legend
            # :top puts it above and shifts the panels down by 80 + 12
            top = storyboard(paths; legend=SVG_LEGEND, legend_position=:top, output=nothing)
            @test occursin("x=\"274.0\" y=\"12.0\"", top)
            @test occursin("x=\"12.0\" y=\"104.0\"", top)
        end
    end

    @testset "legend — a too-narrow cell rejects an external legend" begin
        withtmpsvgs(SVG_SQUARE, SVG_TALL, SVG_SQUARE) do paths
            panels = [Panel(paths[1]; title="A"), Panel(paths[2]; title="B"), Panel(paths[3]; title="C")]
            # 1440 wide into one 300px cell is 0.21 — under the 0.7 floor, so it bands instead
            svg = montage(panels; legend=SVG_LEGEND_WIDE, output=nothing)
            @test occursin("width=\"612.0\" height=\"110.5\"", svg)   # shrunk to the band width
            @test occursin("height=\"1426.5\"", svg)                    # 1304 + 110.5 + 12
            # an explicit cell overrides the floor and squeezes it in
            forced = montage(panels; legend=SVG_LEGEND_WIDE, legend_position=(2, 2), output=nothing)
            @test occursin("height=\"1304.0\"", forced)
            @test occursin("width=\"300.0\"", forced)
        end
    end

    @testset "legend — explicit cell grows the grid; collisions warn" begin
        withtmpsvgs(SVG_SQUARE, SVG_SQUARE, SVG_SQUARE) do paths
            # (2,1) is past the single row, so the grid gains a row: 2*300 + 3*12 = 636
            svg = storyboard(paths; legend=SVG_LEGEND, legend_position=(2, 1), output=nothing)
            @test occursin("height=\"636.0\"", svg)
            # the 300px cell is narrower than the 400px legend, so it shrinks to fit
            @test occursin("x=\"12.0\" y=\"444.0\" width=\"300.0\" height=\"60.0\"", svg)
            # a cell already holding a panel warns
            @test_logs (:warn,) match_mode=:any storyboard(paths; legend=SVG_LEGEND,
                                                           legend_position=(1, 1), output=nothing)
            # off-grid columns are an error
            @test_throws ErrorException storyboard(paths; legend=SVG_LEGEND,
                                                  legend_position=(1, 9), output=nothing)
        end
    end

    @testset "legend — carried through movies" begin
        withtmpsvgs(SVG_SQUARE, SVG_SQUARE, SVG_SQUARE, SVG_SQUARE) do paths
            spec = montage([Panel([paths[1], paths[2]]; title="A"),
                            Panel([paths[3], paths[4]]; title="B")];
                           legend=[("nk", "green")], output=nothing)
            @test spec isa MontageSpec
            @test spec.legend_svg == [("nk", "green")]
            @test spec.legend_position === :auto
            @test spec.legend_font_size == 22.0
            # every frame draws the same legend (flat, so the <svg> count is unchanged)
            for t in 1:spec.nframes
                @test occursin(">nk<", Montage._svgFrame(spec, t))
                @test count("<svg", Montage._svgFrame(spec, t)) == 3
            end
            # the old five-argument constructor still works, and means "no legend"
            old = MontageSpec(spec.panels, spec.nframes, 300.0, 34.0, 12.0)
            @test old.legend_svg === nothing
            @test !occursin(">nk<", Montage._svgFrame(old, 1))
        end
    end

end
