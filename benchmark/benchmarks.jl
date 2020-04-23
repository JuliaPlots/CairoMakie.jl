using BenchmarkTools, CairoMakie, AbstractPlotting

SUITE = BenchmarkGroup()

include("meshes.jl")

include("text.jl")

include("lines.jl")
