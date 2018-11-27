using CairoMakie, Makie, MakieGallery

AbstractPlotting.current_backend[] = CairoMakie.CairoBackend(joinpath(homedir(), "Desktop", "test.png"))
display(scatter(rand(10)))
