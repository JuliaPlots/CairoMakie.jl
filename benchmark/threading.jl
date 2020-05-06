using AbstractPlotting, CairoMakie, MakieLayout, BenchmarkTools

function scene_generator(i::Int)
   return heatmap(rand(500, 500); show_axis = false)
end

scene_generator(1) |> CairoMakie.CairoScreen |> AbstractPlotting.colorbuffer

function render_without_threads(N = 40)
   scenes = [scene_generator(i) for i in 1:N]
   for scene in scenes
      AbstractPlotting.colorbuffer(CairoMakie.CairoScreen(scene))
   end
end

function render_with_threads(N = 40)
   scenes = [scene_generator(i) for i in 1:N]
   Threads.@threads for scene in scenes
      AbstractPlotting.colorbuffer(CairoMakie.CairoScreen(scene))
   end
end

@btime render_without_threads()
@btime render_with_threads()
