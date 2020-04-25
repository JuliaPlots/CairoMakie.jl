####################################################################################################
#                                          Infrastructure                                          #
####################################################################################################

################################################################################
#                                    Types                                     #
################################################################################

@enum RenderType SVG PNG PDF EPS

"The Cairo backend object.  Used to dispatch to CairoMakie methods."
struct CairoBackend <: AbstractPlotting.AbstractBackend
    typ::RenderType
    path::String
end

"""
    struct CairoScreen{S} <: AbstractScreen

A "screen" type for CairoMakie, which encodes a surface
and a context which are used to draw a Scene.
ß"""
struct CairoScreen{S} <: AbstractPlotting.AbstractScreen
    scene::Scene
    surface::S
    context::CairoContext
    pane::Nothing # TODO: Union{CairoGtkPane, Void}
    timer::TimerOutput
end


function CairoBackend(path::String)
    ext = splitext(path)[2]
    typ = if ext == ".png"
        PNG
    elseif ext == ".svg"
        SVG
    elseif ext == ".pdf"
        PDF
    elseif ext == ".eps"
        EPS
    else
        error("Unsupported extension: $ext")
    end
    CairoBackend(typ, path)
end

# we render the scene directly, since we have
# no screen dependent state like in e.g. opengl
Base.insert!(screen::CairoScreen, scene::Scene, plot) = nothing

function Base.show(io::IO, ::MIME"text/plain", screen::CairoScreen{S}) where S
    println(io, "CairoScreen{$S} with surface:")
    println(io, screen.surface)
end

CairoScreen(scene, surf, ctx, pane) = CairoScreen(scene, surf, ctx, pane, TimerOutput())

# Default to ARGB Surface as backing device
# TODO: integrate Gtk into this, so we can have an interactive display
"""
    CairoScreen(scene::Scene; antialias = Cairo.ANTIALIAS_BEST)

Create a CairoScreen backed by an image surface.
"""
function CairoScreen(scene::Scene; antialias = Cairo.ANTIALIAS_BEST)
    w, h = size(scene)
    surf = Cairo.CairoARGBSurface(w, h)
    ctx = CairoContext(surf)
    Cairo.set_antialias(ctx, antialias)

    return CairoScreen(scene, surf, ctx, nothing, TimerOutput("png"))
end

"""
    CairoScreen(
        scene::Scene, path::Union{String, IO};
        mode = :svg, antialias = Cairo.ANTIALIAS_BEST
    )

Creates a CairoScreen pointing to a given output path, with some rendering type defined by `mode`.
"""
function CairoScreen(scene::Scene, path::Union{String, IO}; mode = :svg, antialias = Cairo.ANTIALIAS_BEST)
    w, h = round.(Int, scene.camera.resolution[])

    if mode == :svg
        surf = CairoSVGSurface(path, w, h)
    elseif mode == :pdf
        surf = CairoPDFSurface(path, w, h)
    elseif mode == :eps
        surf = Cairo.CairoEPSSurface(path, w, h)
    elseif mode == :png
        surf = CairoARGBSurface(w, h)
    else
        error("No available Cairo surface for mode $mode")
    end

    ctx = CairoContext(surf)
    Cairo.set_antialias(ctx, antialias)

    return CairoScreen(scene, surf, ctx, nothing, TimerOutput(string(mode)))
end


function Base.delete!(screen::CairoScreen, scene::Scene, plot::AbstractPlot)
    # Currently, we rerender every time, so nothing needs
    # to happen here.  However, in the event that changes,
    # e.g. if we integrate a Gtk window, we may need to
    # do something here.
end

"Convert a rendering type to a MIME type"
function to_mime(x::RenderType)
    x == SVG && return MIME("image/svg+xml")
    x == PDF && return MIME("application/pdf")
    x == EPS && return MIME("application/postscript")
    return MIME("image/png")
end
to_mime(x::CairoBackend) = to_mime(x.typ)

################################################################################
#                              Rendering pipeline                              #
################################################################################

########################################
#           Drawing pipeline           #
########################################

# The main entry point into the drawing pipeline
function cairo_draw(screen::CairoScreen, scene::Scene)
    AbstractPlotting.update!(scene)
    draw_background(screen, scene)
    draw_plot(screen, scene)
    return
end


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

function draw_background(screen::CairoScreen, scene::Scene)
    cr = screen.context
    Cairo.save(cr)
    if scene.clear[]
        bg = to_color(theme(scene, :backgroundcolor)[])
        Cairo.set_source_rgba(cr, red(bg), green(bg), blue(bg), alpha(bg));
        r = pixelarea(scene)[]
        Cairo.rectangle(cr, origin(r)..., widths(r)...) # background
        fill(cr)
    end
    Cairo.restore(cr)
    foreach(child_scene-> draw_background(screen, child_scene), scene.children)
end

function draw_plot(scene::Scene, screen::CairoScreen, primitive::Combined)

    @timeit_debug screen.timer "$(string(typeof(primitive)))" begin
        if isempty(primitive.plots)
            draw_atomic(scene, screen, primitive)
        else
            for plot in primitive.plots
                if to_value(get(primitive, :visible, true)) == true
                    draw_plot(scene, screen, plot)
                end
            end
        end
    end
end

function draw_atomic(::Scene, ::CairoScreen, x)
    @warn "$(typeof(x)) is not supported by cairo right now"
end

#########################################
# Backend interface to AbstractPlotting #
#########################################


function AbstractPlotting.backend_display(x::CairoBackend, scene::Scene)
    return open(x.path, "w") do io
        AbstractPlotting.backend_show(x, io, to_mime(x), scene)
    end
end

AbstractPlotting.backend_showable(x::CairoBackend, ::MIME"image/svg+xml", scene::Scene) = x.typ == SVG
AbstractPlotting.backend_showable(x::CairoBackend, ::MIME"application/pdf", scene::Scene) = x.typ == PDF
AbstractPlotting.backend_showable(x::CairoBackend, ::MIME"application/postscript", scene::Scene) = x.typ == EPS
AbstractPlotting.backend_showable(x::CairoBackend, ::MIME"image/png", scene::Scene) = x.typ == PNG


function AbstractPlotting.backend_show(x::CairoBackend, io::IO, ::MIME"image/svg+xml", scene::Scene)
    screen = CairoScreen(scene, io; mode = :svg)
    cairo_draw(screen, scene)
    @timeit screen.timer "Finishing" begin
        Cairo.finish(screen.surface)
    end
    return screen
end

function AbstractPlotting.backend_show(x::CairoBackend, io::IO, ::MIME"application/pdf", scene::Scene)
    screen = CairoScreen(scene, io; mode=:pdf)
    cairo_draw(screen, scene)
    @timeit screen.timer "Finishing" begin
        Cairo.finish(screen.surface)
    end
    return screen
end


function AbstractPlotting.backend_show(x::CairoBackend, io::IO, ::MIME"application/postscript", scene::Scene)
    screen = CairoScreen(scene, io; mode=:eps)
    cairo_draw(screen, scene)
    @timeit screen.timer "Finishing" begin
        Cairo.finish(screen.surface)
    end
    return screen
end

function AbstractPlotting.backend_show(x::CairoBackend, io::IO, m::MIME"image/png", scene::Scene)
    screen = CairoScreen(scene)
    cairo_draw(screen, scene)
    @timeit screen.timer "Writing to PNG" begin
        Cairo.write_to_png(screen.surface, io)
    end
    return screen
end

function AbstractPlotting.backend_show(x::CairoBackend, io::IO, m::MIME"image/jpeg", scene::Scene)
    # TODO: depend on OpenJPEG or JPEGTurbo to do in-memory JPEG conversion
    # Not sure how much it matters, though, since no one uses JPEG
    screen = nothing
    open(display_path("png"), "w") do fio
        screen = AbstractPlotting.backend_show(x, fio, MIME("image/png"), scene)
    end
    FileIO.save(FileIO.Stream(format"JPEG", io),  FileIO.load(display_path("png")))
    return screen
end

########################################
#    Fast colorbuffer for recording    #
########################################

function AbstractPlotting.colorbuffer(screen::CairoScreen)
    @timeit_debug screen.timer "Colorbuffer" begin
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
        scr = CairoScreen(scene, surf, ctx, nothing, screen.timer)
        cairo_draw(scr, scene)
    end

    # x and y are flipped - return the transpose
    return transpose(img)
end
