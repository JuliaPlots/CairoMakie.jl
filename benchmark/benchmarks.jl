using BenchmarkTools, CairoMakie, MakieGallery
using CairoMakie.AbstractPlotting

results_dir = joinpath(@__DIR__, "results")

isdir(results_dir) && rm(results_dir; recursive = true)
mkpath(results_dir)
cd(results_dir)

SUITE = BenchmarkGroup()

include("triangulation_utils.jl")

# benchmark a Scene

scenesuite = SUITE["scenes"] = BenchmarkGroup(["scenes"])

scenesuite["construct"] = @benchmarkable Scene()

for fmt in ("png", "svg", "pdf")
    scenesuite[fmt] = @benchmarkable save("raw_scene.$fmt", sc) setup=(sc=Scene()) teardown=(rm("raw_scene.$fmt"))
end

# benchmark the creation of plots

plotsuite = SUITE["plots"] = BenchmarkGroup(["plots"])

plot_dict = Dict(
    lines!   => (rand(Point2f0, 100),),
    scatter! => (rand(Point2f0, 100),),
    heatmap! => (rand(100, 100),),
    image!   => (rand(AbstractPlotting.Colors.RGBA, 100, 100),),
    text!    => ("hello world\nthis is cairomakie",),
    contour! => (rand(100, 100),),
)

for (plottyp, input) in pairs(plot_dict)
    plotsuite[string(plottyp)] = BenchmarkGroup([string(plottyp)])
    plotsuite[string(plottyp)]["construct"] = @benchmarkable $(plottyp)(sc, $(input)...; show_axis = false, scale_plot = false) setup=(sc = Scene())

    for fmt in ("png", "svg", "pdf")
        sc = Scene()
        plottyp(sc, input...; show_axis = false, scale_plot = false)
        plotsuite[string(plottyp)][fmt] = @benchmarkable save("$(string(plottyp)[1:end-1]).$fmt", sc) teardown=(rm("$(string(plottyp)[1:end-1]).$fmt"))
    end
end
# mesh benchmarks

meshsuite = SUITE["meshes"] = BenchmarkGroup(["meshes"])

sidesizes = [10, 20, 50, 100, 150, 300, 500, 1000]

xs = LinRange.(0, 1, sidesizes)
ys = LinRange.(0, 1, sidesizes)

points, faces = triangulated_grid.(xs, ys)

for (pointvec, facevec) in zip(points, faces)
    gridsize = length(pointvec)
    meshsuite[string(gridsize)] = BenchmarkGroup(["meshes"])
    meshsuite[string(gridsize)]["construct"] = @benchmarkable mesh!(sc, pointvec, facevec; shading = false, color = rand(RGBAf0, length(pointvec)), scale_plot = false) setup=(sc = Scene())
    for fmt in ("png", "svg", "pdf") # the native output types
        meshsuite[string(gridsize)][fmt] = @benchmarkable save("mesh_$gridsize.$fmt", sc) setup=(sc = mesh(pointvec, facevec; shading = false, color = rand(RGBAf0, length(pointvec)), scale_plot = false)) teardown=(rm("mesh_$gridsize.$fmt"))
    end
end
