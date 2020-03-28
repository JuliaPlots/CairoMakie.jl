module CairoMakie

using AbstractPlotting, LinearAlgebra
using Colors, GeometryTypes, FileIO, StaticArrays
import Cairo

using AbstractPlotting: Scene,
      Lines, LineSegments, Text, Image, Heatmap, Scatter, Mesh,
      @key_str, @extractvalue, @get_attribute,
      broadcast_foreach, convert_attribute, to_ndim,
      NativeFont, Combined, to_value, to_colormap,
      extrema_nan

using AbstractPlotting.FreeType
using AbstractPlotting.FreeTypeAbstraction

using Cairo: CairoContext, CairoARGBSurface, CairoSVGSurface, CairoPDFSurface

include("cairo_ext.jl")

include("infrastructure.jl")
include("utils.jl")
include("primitives.jl")

function __init__()
    activate!()
    AbstractPlotting.register_backend!(AbstractPlotting.current_backend[])
end

function display_path(type::String)
    if !(type in ("svg", "png", "pdf"))
        error("Only \"svg\", \"png\" and \"pdf\" are allowed for `type`. Found: $(type)")
    end
    return joinpath(@__DIR__, "display." * type)
end

function activate!(; inline = true, type = "png")
    AbstractPlotting.current_backend[] = CairoBackend(display_path(type))
    AbstractPlotting.use_display[] = !inline
    return
end

end
