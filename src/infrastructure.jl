################################################################################
#                         Backend struct and utilities                         #
################################################################################

"Defines surfaces which we can render to using Cairo."
@enum RenderType SVG PNG PDF

function to_mime(x::RenderType)
    x == SVG && return MIME"image/svg+xml"()
    x == PDF && return MIME"application/pdf"()
    return MIME"image/png"()
end

"Encodes the surface type and the path to render to."
struct CairoBackend <: AbstractPlotting.AbstractBackend
    typ::RenderType
    path::String
end

to_mime(x::CairoBackend) = to_mime(x.typ)

function CairoBackend(path::String)
    ext = splitext(path)[2]
    typ = if ext == ".png"
        PNG
    elseif ext == ".svg"
        SVG
    elseif ext == ".pdf"
        PDF
    else
        error("Unsupported extension: $ext")
    end
    CairoBackend(typ, path)
end

################################################################################
#                       Screen and rendering management                        #
################################################################################

struct CairoScreen{S} <: AbstractPlotting.AbstractScreen
    scene::Scene
    surface::S
    context::CairoContext
    pane::Nothing#Union{CairoGtkPane, Void}
end
# # we render the scene directly, since we have no screen dependant state like in e.g. opengl
Base.insert!(screen::CairoScreen, scene::Scene, plot) = nothing

function Base.show(io::IO, ::MIME"text/plain", screen::CairoScreen{S}) where S
    println(io, "CairoScreen{$S} with surface:")
    println(io, screen.surface)
end

# Default to Window+Canvas as backing device
function CairoScreen(scene::Scene)
    w, h = size(scene)
    surf = CairoARGBSurface(w, h)
    ctx = CairoContext(surf)
    CairoScreen(scene, surf, ctx, nothing)
end

function CairoScreen(scene::Scene, path::Union{String, IO}; mode = :svg)
    w, h = round.(Int, scene.camera.resolution[])
    # TODO: Add other surface types (PDF, etc.)
    if mode == :svg
        surf = CairoSVGSurface(path, w, h)
    elseif mode == :pdf
        surf = CairoPDFSurface(path, w, h)
    else
        error("No available Cairo surface for mode $mode")
    end
    ctx = CairoContext(surf)
    CairoScreen(scene, surf, ctx, nothing)
end

################################################################################
#                              Rendering to files                              #
################################################################################

AbstractPlotting.backend_showable(x::CairoBackend, m::MIME"image/svg+xml", scene::Scene) = x.typ == SVG
AbstractPlotting.backend_showable(x::CairoBackend, m::MIME"application/pdf", scene::Scene) = x.typ == PDF
AbstractPlotting.backend_showable(x::CairoBackend, m::MIME"image/png", scene::Scene) = x.typ == PNG


function AbstractPlotting.backend_show(x::CairoBackend, io::IO, ::MIME"image/svg+xml", scene::Scene)
    screen = CairoScreen(scene, io)
    cairo_draw(screen, scene)
    Cairo.finish(screen.surface)
    return screen
end

function AbstractPlotting.backend_show(x::CairoBackend, io::IO, ::MIME"application/pdf", scene::Scene)
    screen = CairoScreen(scene, io,mode=:pdf)
    cairo_draw(screen, scene)
    Cairo.finish(screen.surface)
    return screen
end

function AbstractPlotting.backend_show(x::CairoBackend, io::IO, m::MIME"image/png", scene::Scene)
    screen = CairoScreen(scene, io)
    cairo_draw(screen, scene)
    Cairo.write_to_png(screen.surface, io)
    return screen
end

function AbstractPlotting.backend_show(x::CairoBackend, io::IO, m::MIME"image/jpeg", scene::Scene)
    screen = nothing
    open(display_path("png"), "w") do fio
        screen = AbstractPlotting.backend_show(x, fio, MIME"image/png"(), scene)
    end
    FileIO.save(FileIO.Stream(format"JPEG", io),  FileIO.load(display_path("png")))
    return screen
end

function AbstractPlotting.backend_display(x::CairoBackend, scene::Scene)
    return open(x.path, "w") do io
        AbstractPlotting.backend_show(x, io, to_mime(x), scene)
    end
end

################################################################################
#                               Drawing pipeline                               #
################################################################################

# The main entry point to the backend
function cairo_draw(screen::CairoScreen, scene::Scene)
    AbstractPlotting.update!(scene)
    draw_background(screen, scene)
    draw_plot(screen, scene)
    return
end

function cairo_clear(screen::CairoScreen)
    ctx = screen.context
    w, h = Cairo.width(ctx), Cairo.height(ctx)
    Cairo.rectangle(ctx, 0, 0, w, h)
    # FIXME: Cairo.set_source_rgb(ctx, screen.scene.theme[:color]...)
    Cairo.fill(ctx)
end

# Draw a background for a subscene
function draw_background(screen::CairoScreen, scene::Scene)
    cr = screen.context
    Cairo.save(cr)
    if scene.clear[]
        bg = to_color(theme(scene, :backgroundcolor)[])
        Cairo.set_source_rgba(cr, red(bg), green(bg), blue(bg), alpha(bg));    # light gray
        r = pixelarea(scene)[]
        Cairo.rectangle(cr, minimum(r)..., widths(r)...) # background
        fill(cr)
    end
    Cairo.restore(cr)
    foreach(child_scene-> draw_background(screen, child_scene), scene.children)
end

# Draws the root scene
function draw_plot(screen::CairoScreen, scene::Scene)

    # get the root area to correct for its pixel size when translating
    root_area = AbstractPlotting.root(scene).px_area[]

    root_area_height = widths(root_area)[2]
    scene_area = pixelarea(scene)[]
    scene_height = widths(scene_area)[2]
    scene_x_origin, scene_y_origin = scene_area.origin

    Cairo.save(screen.context)

    # we need to translate x by the origin, so distance from the left
    # but y by the distance from the top, which is not the origin, but can
    # be calculated using the parent's height, the scene's height and the y origin
    # this is because y goes downwards in Cairo and upwards in AbstractPlotting

    top_offset = root_area_height - scene_height - scene_y_origin
    Cairo.translate(screen.context, scene_x_origin, top_offset)

    # clip the scene to its pixelarea
    Cairo.rectangle(screen.context, 0, 0, widths(scene_area)...)
    Cairo.clip(screen.context)

    for elem in scene.plots
        if to_value(get(elem, :visible, true))
             draw_plot(scene, screen, elem)
        end
    end
    Cairo.restore(screen.context)

    for child in scene.children
        draw_plot(screen, child)
    end

    return
end

function draw_plot(scene::Scene, screen::CairoScreen, primitive::Combined)
    isempty(primitive.plots) && return draw_atomic(scene, screen, primitive)
    for plot in primitive.plots
        (plot.visible[] == true) && draw_plot(scene, screen, plot)
    end
end

function draw_atomic(::Scene, ::CairoScreen, x)
    @warn "$(typeof(x)) is not supported by cairo right now"
end

################################################################################
#                                 Colorbuffer                                  #
################################################################################

# This is used for AbstractPlotting's recording function
function AbstractPlotting.colorbuffer(screen::CairoScreen)
    # extract scene
    scene = screen.scene
    # get resolution
    w, h = size(scene)
    # preallocate an image matrix
    img = Matrix{ARGB32}(undef, w, h)
    # create an image surface to draw onto the image
    surf = Cairo.CairoImageSurface(img)
    # draw the scene onto the image matrix
    ctx = Cairo.CairoContext(surf)
    scr = CairoScreen(scene, surf, ctx, nothing)
    cairo_draw(scr, scene)

    # x and y are flipped - return the transpose
    return transpose(img)

end
