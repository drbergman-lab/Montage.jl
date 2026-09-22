using Montage
using Documenter

# The weak dependencies, loaded so that every package extension is present during the
# build: the methods they add are part of Montage's API, and their docstrings are
# rendered and checked exactly like the core's.
using CairoMakie, PhysiCellOutput, PhysiCellModelManager, Rsvg, Cairo, FFMPEG

# Bind each extension module in `Main` under its own name, so the reference page can
# name it in an `@autodocs` block. A missing one is a build error rather than a
# quietly half-empty API reference.
const EXTENSIONS = [:MontageMovieExt, :MontagePhysiCellOutputExt, :MontagePhysiCellModelManagerExt,
                    :MontageCairoMakieExt, :MontageCairoMakiePhysiCellOutputExt, :MontageCairoMakiePCMMExt]
for name in EXTENSIONS
    ext = Base.get_extension(Montage, name)
    ext === nothing && error("""
        extension $name did not load, so its docstrings would be missing from the manual.
        Check `[weakdeps]`/`[extensions]` in Project.toml and the versions in docs/Project.toml.""")
    @eval const $name = $ext
end

# Regenerate docs/src/dev/journal.md from the `!!! tierjournal` blocks on the pages,
# and check that every page's tier blocks run shallowest first.
include("journal.jl")

DocMeta.setdocmeta!(Montage, :DocTestSetup, :(using Montage); recursive=true)

makedocs(;
    modules=[Montage, (getfield(Main, name) for name in EXTENSIONS)...],
    authors="Daniel Bergman <danielrbergman@gmail.com> and contributors",
    sitename="Montage.jl",
    format=Documenter.HTML(;
        canonical="https://drbergman-lab.github.io/Montage.jl",
        edit_link="main",
        assets=["assets/tiers.css", "assets/tiers.js"],
    ),
    checkdocs=:all,
    pages=[
        "Home" => "index.md",
        "Manual" => [
            "man/montage.md",
            "man/storyboard.md",
            "man/tableau.md",
            "man/movies.md",
            "man/physicell.md",
            "man/extensions.md",
        ],
        "API reference" => "reference.md",
        "Developers" => [
            "Architecture" => "dev/architecture.md",
            "Journal" => "dev/journal.md",
        ],
    ],
)

deploydocs(;
    repo="github.com/drbergman-lab/Montage.jl",
    devbranch="main",
)
