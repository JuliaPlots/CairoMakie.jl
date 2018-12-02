using ImageMagick
using CairoMakie, AbstractPlotting, MakieGallery

tmp = joinpath(@__DIR__, "test.png")
AbstractPlotting.current_backend[] = CairoMakie.CairoBackend(tmp)
database = MakieGallery.load_database()
filter!(database) do entry
    "2d" in entry.tags &&
    "Text rotation" != entry.title &&
    "fem polygon 2d" != lowercase(entry.title) &&
    "Hbox" != entry.title &&
    !("heatmap" in entry.tags) && # why though, they worked -.-
    !("image" in entry.tags)
end

ref_path = MakieGallery.download_reference(v"0.0.9")

tested_diff_path = joinpath(@__DIR__, "tested_different")
test_record_path = joinpath(@__DIR__, "test_recordings")
rm(tested_diff_path, force = true, recursive = true)
mkpath(tested_diff_path)
rm(test_record_path, force = true, recursive = true)
mkpath(test_record_path)

MakieGallery.record_examples(test_record_path)
MakieGallery.run_comparison(test_record_path, ref_path, tested_diff_path)
rm(tmp, force = true)
