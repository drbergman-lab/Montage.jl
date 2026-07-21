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
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/drbergman-lab/Montage.jl",
    devbranch="main",
)
