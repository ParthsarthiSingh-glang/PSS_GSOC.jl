using Documenter, Jerbie

include("pages.jl")

makedocs(
    sitename = "Jerbie.jl",
    modules = [Jerbie],
    clean = true, doctest = true, checkdocs = :exports,
    format = Documenter.HTML(),
    pages = pages
)

deploydocs(repo = "github.com/ParthsarthiSingh-glang/Jerbie.jl.git"; push_preview = true)
