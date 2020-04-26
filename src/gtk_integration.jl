using Gtk, AbstractPlotting, CairoMakie, Cairo, Colors, TimerOutputs

struct GtkScreen
   scene::Scene
   window::Gtk.GtkWindow
   canvas::Gtk.GtkCanvas
   timer::TimerOutput
end

function Base.getproperty(gs::GtkScreen, s::Symbol)

   s in fieldnames(GtkScreen) && return getfield(gs, s)

   if s == :context
      return Gtk.getgc(gs.canvas)
   elseif s == :surface
      return Gtk.cairo_surface(gs.canvas)
   end

   throw(KeyError(s))
end

function attach(canvas, scene, timer = TimerOutput())
    @guarded draw(canvas) do _
      println("Drawing")
       resize!(scene, Gtk.width(canvas), Gtk.height(canvas))
       screen = CairoMakie.CairoScreen(scene, Gtk.cairo_surface(canvas), getgc(canvas), nothing, timer)
       CairoMakie.cairo_draw(screen, scene)
    end
end

function Base.convert(::Type{Colors.RGBA}, c::Gtk.RGBA)
   Colors.RGBA(Colors.FixedPointNumbers.N0f8.(((c.r, c.g, c.b, c.a) ./ 255))...)
end

function Base.show(io::IO, ::MIME"text/plain", gs::GtkScreen)
   println(io, "GtkScreen()")
end

function GtkScreen(scene::Scene)

   canvas = @GtkCanvas()

   window = GtkWindow(canvas, "Makie", scene.camera.resolution[]...)

   show(canvas);

   timer = TimerOutput("GTK")

   attach(canvas, scene, timer)

   return GtkScreen(scene, window, canvas, timer)

   return screen

end

function AbstractPlotting.colorbuffer(screen::GtkScreen)
   @timeit_debug screen.timer "Colorbuffer" begin
      @timeit_debug screen.timer "Drawing" begin
         draw(screen.canvas, true)
      end

      @timeit_debug screen.timer "Pixbuffing" begin
         gdk_pix = ccall(
            (:gdk_pixbuf_get_from_surface, Gtk.libgdk),
            Ptr{Gtk.GObject},
            (Ptr{Cvoid}, Cint, Cint, Cint, Cint),
            Gtk.cairo_surface(screen.canvas).ptr, 0, 0, Gtk.width(screen.canvas), Gtk.height(screen.canvas)
         ) |> Gtk.GdkPixbuf
      end

      @timeit_debug screen.timer "Converting" begin
         mat = convert(Gtk.MatrixStrided, Gtk.GdkPixbuf(gdk_pix_s))
         tr = transpose(Colors.RGBA.(mat))
      end
   end
   return tr
end






scene = lines(rand(10));

for i in 1:10
   lines!(scene, rand(10))
end


screen = GtkScreen(scene)

AbstractPlotting.colorbuffer(screen)

screen.timer

@benchmark AbstractPlotting.colorbuffer(screen)

@benchmark AbstractPlotting.colorbuffer(CairoMakie.CairoScreen(scene))
