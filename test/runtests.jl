using ImageMagick, Test
using CairoMakie, AbstractPlotting, MakieGallery
CairoMakie.activate!(type = "png")

# AbstractPlotting.format2mime(::Type{AbstractPlotting.FileIO.format"PDF"}) = MIME("application/pdf")

include("saving.jl") # test saving params

database = MakieGallery.load_database()

filter!(database) do entry
    "2d" in entry.tags &&
    !("3d" in entry.tags) &&
    lowercase(entry.title) != "arrows on hemisphere" &&
    !(lowercase(entry.title) ∈ (
        "arrows on hemisphere",
        "cobweb plot",
        "edit polygon",  # pick not implemented yet
        "orbit diagram", # really slow
    ))
end

tested_diff_path = joinpath(@__DIR__, "tested_different")
test_record_path = joinpath(@__DIR__, "test_recordings")
rm(tested_diff_path, force = true, recursive = true)
mkpath(tested_diff_path)
rm(test_record_path, force = true, recursive = true)
mkpath(test_record_path)

MakieGallery.record_examples(test_record_path)
MakieGallery.run_comparison(test_record_path, tested_diff_path)

MakieGallery.load_database([
        "tutorials.jl",
        "attributes.jl",
        "intermediate.jl",
        "examples2d.jl",
        "examples3d.jl",
        "interactive.jl",
        "documentation.jl",
        "diffeq.jl",
        "implicits.jl",
        "short_tests.jl",
        "recipes.jl",
        "bigdata.jl",
        "layouting.jl",
        "legends.jl",
        "statsmakie.jl",
        # "geomakie.jl",
    ] .|> x -> joinpath("/Users/anshul/jdev/MakieGallery/examples", x))
