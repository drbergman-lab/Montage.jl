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

end
