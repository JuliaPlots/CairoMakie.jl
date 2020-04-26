
"This is essentially an enum."
const CAIRO_SURFACE_MAP = [
    "IMAGE"         ,
    "PDF"           ,
    "PS"            ,
    "XLIB"          ,
    "XCB"           ,
    "GLITZ"         ,
    "QUARTZ"        ,
    "WIN32"         ,
    "BEOS"          ,
    "DIRECTFB"      ,
    "SVG"           ,
    "OS2"           ,
    "WIN32_PRINTING",
    "QUARTZ_IMAGE"  ,
    "SCRIPT"        ,
    "QT"            ,
    "RECORDING"     ,
    "VG"            ,
    "GL"            ,
    "DRM"           ,
    "TEE"           ,
    "XML"           ,
    "SKIA"          ,
    "SUBSURFACE"    ,
    "COGL"          ,
]

const VECTOR_BACKEND_TYPES = Set((
    "PDF",
    "PS",
    "SVG",
    "SCRIPT",
    "RECORDING",
    "SUBSURFACE"
))


function should_render_text(i::Int32)
    return CAIRO_SURFACE_MAP[i+1] ∈ VECTOR_BACKEND_TYPES
end

"""
Returns `true` if you should use real text rendering,
and `false` if you should use text paths.
"""
function should_render_text(surf)
    return should_render_text(ccall((:cairo_surface_get_type, CairoMakie.LIB_CAIRO), Cint, (Ptr{Cvoid},), screen.surface.ptr))
end
