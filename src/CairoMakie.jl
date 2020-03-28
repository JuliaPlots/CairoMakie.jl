module CairoMakie

using AbstractPlotting, LinearAlgebra
using Colors, GeometryTypes, FileIO, StaticArrays
import Cairo

using AbstractPlotting: Scene, Lines, Text, Image, Heatmap, Scatter, @key_str, broadcast_foreach
using AbstractPlotting: convert_attribute, @extractvalue, LineSegments, to_ndim, NativeFont
using AbstractPlotting: @info, @get_attribute, Combined
using AbstractPlotting: to_value, to_colormap, extrema_nan
using Cairo: CairoContext, CairoARGBSurface, CairoSVGSurface, CairoPDFSurface

const LIB_CAIRO = if isdefined(Cairo, :libcairo)
    Cairo.libcairo
else
    Cairo._jl_libcairo
end

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

function activate!(; inline = true, type = "svg")
    AbstractPlotting.current_backend[] = CairoBackend(display_path(type))
    AbstractPlotting.use_display[] = !inline
    return
end

end
