using ImageMagick
using CairoMakie, AbstractPlotting, MakieGallery
CairoMakie.activate!(type = "png")

database = MakieGallery.load_database()
filter!(database) do entry
    "2d" in entry.tags &&
    !(lowercase(entry.title) ∈ ("arrows on hemisphere", "cobweb plot", "lots_of_heatmaps", "streamplot animation"))
end

empty!(MakieGallery.plotting_backends)
push!(MakieGallery.plotting_backends, "AbstractPlotting", "CairoMakie")
tested_diff_path = joinpath(@__DIR__, "tested_different")
test_record_path = joinpath(@__DIR__, "test_recordings")
rm(tested_diff_path, force = true, recursive = true)
mkpath(tested_diff_path)
rm(test_record_path, force = true, recursive = true)
mkpath(test_record_path)

MakieGallery.record_examples(test_record_path)
MakieGallery.run_comparison(test_record_path, tested_diff_path)

include("saving.jl")
