using Montage
using Documenter

DocMeta.setdocmeta!(Montage, :DocTestSetup, :(using Montage); recursive=true)

makedocs(;
    modules=[Montage],
    authors="Daniel Bergman <danielrbergman@gmail.com> and contributors",
    sitename="Montage.jl",
    format=Documenter.HTML(;
        canonical="https://drbergman-lab.github.io/Montage.jl",
        edit_link="main",
        assets=String[],
    ),
    checkdocs=:exports,
    pages=[
        "Home" => "index.md",
        "Manual" => [
            "man/montage.md",
            "man/storyboard.md",
            "man/tableau.md",
            "man/movies.md",
            "man/extensions.md",
        ],
        "API reference" => "reference.md",
    ],
)

deploydocs(;
    repo="github.com/drbergman-lab/Montage.jl",
    devbranch="main",
)
