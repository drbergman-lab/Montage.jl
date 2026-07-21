using Montage
using Test

# Tiny hand-written SVGs of differing intrinsic sizes to exercise the max-aspect
# grid logic — no PCMM, no CairoMakie, no external fixtures.
const SVG_SQUARE = """<?xml version="1.0"?>
<svg width="100" height="100" xmlns="http://www.w3.org/2000/svg"><rect width="100" height="100" fill="red"/></svg>"""
const SVG_TALL = """<svg width="100" height="200" xmlns="http://www.w3.org/2000/svg"><rect width="100" height="200" fill="blue"/></svg>"""

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
            svg = montage(panels; panel_width=300, title_height=34, pad=12)
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
            svg = montage(paths; panel_width=300, title_height=34, pad=12)  # loose, untitled
            @test !occursin("<text", svg)
            # n=2 -> ncols=2, nrows=1; no band; aspect=1 -> panel_height=300, cell_h=300
            # total_h = 1*300 + 2*12 = 324
            @test occursin("height=\"324.0\"", svg)
        end
    end

    @testset "title XML-escaping" begin
        withtmpsvgs(SVG_SQUARE) do paths
            svg = montage([Panel(paths[1]; title="a & b <c>")])
            @test occursin("a &amp; b &lt;c&gt;", svg)
        end
    end

    @testset "output kwarg writes a file" begin
        withtmpsvgs(SVG_SQUARE) do paths
            out = joinpath(mktempdir(), "sub", "grid.svg")
            ret = montage(paths; output=out)
            @test isfile(out)
            @test read(out, String) == ret
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
            # two animated panels, 2 frames each -> a MontageSpec, not an SVG string
            spec = montage([Panel([paths[1], paths[2]]; title="A"),
                            Panel([paths[3], paths[4]]; title="B")])
            @test spec isa MontageSpec
            @test spec.nframes == 2
            @test length(spec.panels) == 2
            # per-frame SVG reuses the static stitcher: root + one child per panel
            f1 = Montage._svgFrame(spec, 1)
            @test occursin(">A<", f1) && occursin(">B<", f1)
            @test count("<svg", f1) == 3
            @test_throws BoundsError Montage._svgFrame(spec, 3)
            # record without the movie extension loaded -> helpful error
            @test_throws ErrorException record(spec, joinpath(mktempdir(), "x.mp4"))
        end
    end

    @testset "montage movie — index truncation + warning" begin
        withtmpsvgs(SVG_SQUARE, SVG_SQUARE, SVG_SQUARE) do paths
            local spec
            @test_logs (:warn,) match_mode=:any begin
                spec = montage([Panel([paths[1], paths[2]]),   # 2 frames
                                Panel([paths[3]])])            # 1 frame
            end
            @test spec.nframes == 1                             # truncated to shortest
        end
        # all panels must be animated for a movie spec
        withtmpsvgs(SVG_SQUARE, SVG_SQUARE) do paths
            @test montage([Panel(paths[1]), Panel(paths[2])]) isa String   # both static -> SVG
        end
    end

end
