# # Mesh testing and benchmarking
# This test file benchmarks the speed of CairoMakie at typesetting meshes
# on several different output types (PNG, PDF, SVG, EPS).

MESHES = SUITE["meshes"] = BenchmarkGroup(["meshes"])

using GeoMakie, BenchmarkTools

range_sizes = round.(Int, exp.(LinRange(2, 8, 10)))

source = LonLat()
dest = WinkelTripel()

lon_ranges = LinRange.(-179.5, 179.5, range_sizes)
lat_ranges = LinRange.(-89.5, 89.5, range_sizes)

fields = [[exp(cosd(l)) + 3(y/90) for l in lons, y in lats] for (lons, lats) in zip(lon_ranges, lat_ranges)]

pointsfaces = GeoMakie.triangulated_grid.(lon_ranges, lat_ranges)

tpoints = map(x -> transform.(source, dest, x), getindex.(pointsfaces, 1))
faces = getindex.(pointsfaces, 2)

scenes = [mesh(tpoint, face; scale_plot = false, show_axis = false, shading = false, color = GeoMakie.img2colorvec(field), resolution = (1000, 500)) for (tpoint, face, field) in zip(tpoints, faces, fields)]

CairoMakie.save("test.png", scenes[4])

png_benches = MESHES["png"] = BenchmarkGroup(["png", "meshes"])
pdf_benches = MESHES["pdf"] = BenchmarkGroup(["pdf", "meshes"])
svg_benches = MESHES["svg"] = BenchmarkGroup(["svg", "meshes"])
eps_benches = MESHES["eps"] = BenchmarkGroup(["eps", "meshes"])

for i in 1:length(scenes)
    filename = "mesh_$i"
    png_benches[range_sizes[i]] = @benchmarkable save($(filename * ".png"), $(scenes[i]))
    pdf_benches[range_sizes[i]] = @benchmarkable save($(filename * ".pdf"), $(scenes[i]))
    svg_benches[range_sizes[i]] = @benchmarkable save($(filename * ".svg"), $(scenes[i]))
    eps_benches[range_sizes[i]] = @benchmarkable save($(filename * ".eps"), $(scenes[i]))
end

results = run(SUITE, verbose = true)
