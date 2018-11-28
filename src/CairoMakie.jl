module CairoMakie

using AbstractPlotting
using AbstractPlotting: Scene, Lines, Text, Image, Heatmap, Scatter, @key_str, broadcast_foreach
using AbstractPlotting: convert_attribute, @extractvalue, LineSegments, to_ndim, NativeFont
using AbstractPlotting: @info, @get_attribute, Combined
using Colors, GeometryTypes
using AbstractPlotting: to_value, to_colormap, extrema_nan
using Cairo

@enum RenderType SVG PNG

struct CairoBackend <: AbstractPlotting.AbstractBackend
    typ::RenderType
    path::String
end

function to_mime(x::RenderType)
    x == SVG && return MIME"image/svg+xml"()
    return MIME"image/png"()
end
to_mime(x::CairoBackend) = to_mime(x.typ)

function CairoBackend(path::String)
    ext = splitext(path)[2]
    typ = if ext == ".png"
        PNG
    elseif ext == ".svg"
        SVG
    else
        error("Unsupported extension: $ext")
    end
    CairoBackend(typ, path)
end

struct CairoScreen{S}
    scene::Scene
    surface::S
    context::CairoContext
    pane::Nothing#Union{CairoGtkPane, Void}
end
# # we render the scene directly, since we have no screen dependant state like in e.g. opengl
Base.insert!(screen::CairoScreen, scene::Scene, plot) = nothing

# Default to Gtk Window+Canvas as backing device
function CairoScreen(scene::Scene)
    w, h = round.(Int, scene.camera.resolution[])
    surf = CairoRGBSurface(w, h)
    ctx = CairoContext(surf)
    CairoScreen(scene, surf, ctx, nothing)
end

function CairoScreen(scene::Scene, path::Union{String, IO}; mode = :svg)
    w, h = round.(Int, scene.camera.resolution[])
    # TODO: Add other surface types (PDF, etc.)
    if mode == :svg
        surf = CairoSVGSurface(path, w, h)
    else
        error("No available Cairo surface for mode $mode")
    end
    ctx = CairoContext(surf)
    CairoScreen(scene, surf, ctx, nothing)
end


function project_position(scene, point, model)
    res = scene.camera.resolution[]
    p4d = to_ndim(Vec4f0, to_ndim(Vec3f0, point, 0f0), 1f0)
    clip = scene.camera.projectionview[] * model * p4d
    p = (clip / clip[4])[Vec(1, 2)]
    p = Vec2f0(p[1], -p[2])
    ((((p + 1f0) / 2f0) .* (res - 1f0)) + 1f0)
end
project_scale(scene::Scene, s::Number) = project_scale(scene, Vec2f0(s))
function project_scale(scene::Scene, s)
    p4d = to_ndim(Vec4f0, s, 0f0)
    p = (scene.camera.projectionview[] * p4d)[Vec(1, 2)] ./ 2f0
    p .* scene.camera.resolution[]
end

function draw_segment(scene, ctx, point::Point, model, connect, do_stroke, c, linewidth, linestyle, primitive)
    pos = project_position(scene, point, model)
    function stroke()
        Cairo.set_line_width(ctx, Float64(linewidth))
        Cairo.set_source_rgba(ctx, red(c), green(c), blue(c), alpha(c))
        if linestyle != nothing
            #set_dash(ctx, linestyle, 0.0)
        end
        Cairo.stroke(ctx)
    end
    if !all(isfinite.(pos))
        connect[] = false
    else
        if connect[]
            Cairo.line_to(ctx, pos[1], pos[2])
            isa(primitive, LineSegments) && (connect[] = false)
        end
        if do_stroke[]
            stroke(); do_stroke[] = false; connect[] = true
            Cairo.move_to(ctx, pos[1], pos[2])
        else
            do_stroke[] = true
        end
    end
end

function draw_segment(scene, ctx, segment::Tuple{<: Point, <: Point}, model, connect, do_stroke, c, linewidth, linestyle, primitive)
    a, b = project_position.((scene,), segment, (model,))
    function stroke()
        Cairo.set_line_width(ctx, Float64(linewidth))
        Cairo.set_source_rgba(ctx, red(c), green(c), blue(c), alpha(c))
        if linestyle != nothing
            #set_dash(ctx, linestyle, 0.0)
        end
        Cairo.stroke(ctx)
    end
    Cairo.move_to(ctx, a...)
    Cairo.line_to(ctx, b...)
    stroke()
end

function draw_atomic(screen::CairoScreen, primitive::Union{Lines, LineSegments})
    scene = screen.scene
    fields = @get_attribute(primitive, (color, linewidth, linestyle))
    ctx = screen.context
    model = primitive[:model][]
    positions = primitive[1][]
    isempty(positions) && return
    N = length(positions)
    connect = Ref(true); do_stroke = Ref(true)
    broadcast_foreach(1:N, positions, fields...) do i, point, c, linewidth, linestyle
        draw_segment(scene, ctx, point, model, connect, do_stroke, c, linewidth, linestyle, primitive)
    end
    nothing
end

function to_cairo_image(img::AbstractMatrix{<: AbstractFloat}, attributes)
    AbstractPlotting.@get_attribute attributes (colormap, colorrange)
    imui32 = to_uint32_color.(AbstractPlotting.interpolated_getindex.(Ref(colormap), img, (colorrange,)))
    to_cairo_image(imui32, attributes)
end

function to_cairo_image(img::Matrix{UInt32}, attributes)
    CairoARGBSurface(img)
end
to_uint32_color(c) = reinterpret(UInt32, convert(ARGB32, c))
function to_cairo_image(img, attributes)
    to_cairo_image(to_uint32_color.(img), attributes)
end

function draw_atomic(screen::CairoScreen, primitive::Image)
    draw_image(screen, primitive)
end

function draw_atomic(screen::CairoScreen, primitive::Union{Heatmap, Image})
    draw_image(screen, primitive)
end

function draw_image(screen, attributes)
    scene = screen.scene
    ctx = screen.context
    image = attributes[3][]
    x, y = attributes[1][], attributes[2][]
    model = attributes[:model][]
    imsize = (extrema_nan(x), extrema_nan(y))
    xy = project_position(scene, Point2f0(first.(imsize)), model)
    xymax = project_position(scene, Point2f0(last.(imsize)), model)
    w, h = xymax .- xy
    interp = to_value(get(attributes, :interpolate, true))
    interp = interp ? Cairo.FILTER_BEST : Cairo.FILTER_NEAREST
    Cairo.save(ctx);
    pattern = Cairo.CairoPattern(to_cairo_image(image, attributes))
    Cairo.pattern_set_extend(pattern, Cairo.EXTEND_PAD)
    Cairo.pattern_set_filter(pattern, interp)
    Cairo.set_source(ctx, pattern)
    Cairo.rectangle(ctx, xy..., w, h)
    Cairo.fill(ctx)
    Cairo.restore(ctx)
end


function draw_atomic(screen::CairoScreen, primitive::Scatter)
    scene = screen.scene
    fields = @get_attribute(primitive, (color, markersize, strokecolor, strokewidth, marker))
    ctx = screen.context
    model = primitive[:model][]
    positions = primitive[1][]
    isempty(positions) && return
    broadcast_foreach(primitive[1][], fields...) do point, c, markersize, strokecolor, strokewidth, marker
        # TODO: Implement marker
        # TODO: Accept :radius field or similar?
        scale = project_scale(scene, markersize)
        pos = project_position(scene, point, model)
        Cairo.set_source_rgba(ctx, red(c), green(c), blue(c), alpha(c))
        Cairo.arc(ctx, pos[1], pos[2], scale[1] / 2, 0, 2*pi)
        Cairo.fill(ctx)
        sc = to_color(strokecolor)
        Cairo.set_source_rgba(ctx, red(sc), green(sc), blue(sc), alpha(sc))
        Cairo.set_line_width(ctx, Float64(strokewidth))
        #if linestyle != nothing
        #    set_dash(ctx, convert_attribute(linestyle, key"linestyle"()), 0.0)
        #end
        Cairo.arc(ctx, pos[1], pos[2], scale[1], 0, 2*pi)
        Cairo.stroke(ctx)
    end
    nothing
end





scale_matrix(x, y) = Cairo.CairoMatrix(x, 0.0, 0.0, y, 0.0, 0.0)
function rot_scale_matrix(x, y, q)
    sx, sy, sz = 2q[4]*q[1], 2q[4]*q[2], 2q[4]*q[3]
    xx, xy, xz = 2q[1]^2, 2q[1]*q[2], 2q[1]*q[3]
    yy, yz, zz = 2q[2]^2, 2q[2]*q[3], 2q[3]^2
    m = Cairo.CairoMatrix(
        x, 1 - (xx + zz), yz + sx,
        y, yz - sx, 1 - (xx + yy)
    )
    m
end

function set_font_matrix(cr, matrix)
    ccall((:cairo_set_font_matrix, Cairo._jl_libcairo), Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}), cr.ptr, Ref(matrix))
end


function set_ft_font(cr, font)
    font_face = ccall(
        (:cairo_ft_font_face_create_for_ft_face, Cairo._jl_libcairo),
        Ptr{Cvoid}, (Ptr{Cvoid}, Cint),
        font, 0
    )
    ccall((:cairo_set_font_face, Cairo._jl_libcairo), Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}), cr.ptr, font_face)
end
fontname(x::String) = x
fontname(x::Symbol) = string(x)
function fontname(x::NativeFont)
    ft_rect = unsafe_load(x[1])
    unsafe_string(ft_rect.family_name)
end

function fontscale(scene, c, font, s)
    atlas = AbstractPlotting.get_texture_atlas()
    s = (s ./ atlas.scale[AbstractPlotting.glyph_index!(atlas, c, font)]) ./ 0.02
    project_scale(scene, s)
end

function draw_atomic(screen::CairoScreen, primitive::Text)
    scene = screen.scene
    ctx = screen.context
    @get_attribute(primitive, (textsize, color, font, align, rotation, model))
    txt = to_value(primitive[1])
    position = primitive.attributes[:position][]
    N = length(txt)
    broadcast_foreach(1:N, position, textsize, color, font, rotation) do i, p, ts, cc, f, r
        Cairo.save(ctx)
        pos = project_position(scene, p, model)
        Cairo.move_to(ctx, pos[1], pos[2])
        Cairo.set_source_rgba(ctx, red(cc), green(cc), blue(cc), alpha(cc))

        Cairo.select_font_face(
            ctx, fontname(f),
            Cairo.FONT_SLANT_NORMAL,
            Cairo.FONT_WEIGHT_BOLD
        )
        #set_ft_font(ctx, f)
        char = N == length(position) ? txt[i] : first(txt)
        ts = fontscale(scene, char, f, ts)
        mat = scale_matrix(ts...)
        set_font_matrix(ctx, mat)
        # set_font_size(ctx, 16)
        # TODO this only works in 2d
        rotate(ctx, 2acos(r[4]))
        if N == length(position) # if one position per glyph
            Cairo.show_text(ctx, string(txt[i]))
        else
            Cairo.show_text(ctx, txt)
        end
        Cairo.restore(ctx)
    end
    nothing
end

function cairo_clear(screen::CairoScreen)
    ctx = screen.context
    w, h = Cairo.width(ctx), Cairo.height(ctx)
    Cairo.rectangle(ctx, 0, 0, w, h)
    # FIXME: Cairo.set_source_rgb(ctx, screen.scene.theme[:color]...)
    Cairo.fill(ctx)
end

function cairo_finish(screen::CairoScreen{CairoRGBSurface})
    showall(screen.pane.window)
    draw(screen.pane.canvas) do canvas
        ctx = getgc(canvas)
        w, h = Cairo.width(ctx), Cairo.height(ctx)
        # TODO: Maybe just use set_source(ctx, screen.surface)?
        Cairo.image(ctx, screen.surface, 0, 0, w, h)
    end
end
cairo_finish(screen::CairoScreen) = finish(screen.surface)



function cairo_draw(screen::CairoScreen, primitive::Combined)
    isempty(primitive.plots) && return draw_atomic(screen, primitive)
    for plot in primitive.plots
        cairo_draw(screen, plot)
    end
end

function cairo_draw(screen::CairoScreen, scene::Scene)
    for elem in scene.plots
        cairo_draw(screen, elem)
    end
    foreach(child_scene-> cairo_draw(screen, child_scene), scene.children)
    cairo_finish(screen)
    return
end

function AbstractPlotting.backend_display(x::CairoBackend, scene::Scene)
    open(x.path, "w") do io
        AbstractPlotting.backend_show(x, io, to_mime(x), scene)
    end
end

AbstractPlotting.backend_showable(x::CairoBackend, m::MIME"image/svg+xml", scene::SceneLike) = x.typ == SVG
AbstractPlotting.backend_showable(x::CairoBackend, m::MIME"image/png", scene::SceneLike) = x.typ == PNG


function AbstractPlotting.backend_show(::CairoBackend, io::IO, ::MIME"image/svg+xml", scene::Scene)
    AbstractPlotting.update!(scene)
    screen = CairoScreen(scene, io)
    cairo_draw(screen, scene)
end

function AbstractPlotting.backend_show(::CairoBackend, io::IO, ::MIME"image/png", scene::Scene)
    AbstractPlotting.update!(scene)
    screen = CairoScreen(scene, io)
    cairo_draw(screen, scene)
    write_to_png(screen.surface, io)
end

function __init__()
    dir = mktempdir()
    temp_file = joinpath(dir, "cairo.svg")
    AbstractPlotting.register_backend!(CairoBackend(temp_file))
    atexit() do
        rm(dir, force = true, recursive = true)
    end
end

function activate!(inline = false)
    AbstractPlotting.current_backend[] = CairoBackend()
    AbstractPlotting.use_display[] = !inline
    return
end

end
