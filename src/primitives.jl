################################################################################
#                             Lines, LineSegments                              #
################################################################################

function draw_segment(scene, ctx, point::Point, model, c, linewidth, linestyle, primitive, idx, N)
    pos = project_position(scene, point, model)
    function stroke()
        !isnothing(linestyle) && Cairo.set_dash(ctx, linestyle)
        Cairo.set_line_width(ctx, Float64(linewidth))
        Cairo.set_source_rgba(ctx, red(c), green(c), blue(c), alpha(c))
        if linestyle != nothing
            #set_dash(ctx, linestyle, 0.0)
        end
        Cairo.stroke(ctx)
    end
    if !all(isfinite.(pos))
        stroke() # stroke last points, ignore this one (NaN for disconnects)
    else
        if isa(primitive, LineSegments)
            if isodd(idx) # on each odd move to
                Cairo.move_to(ctx, pos[1], pos[2])
            else
                Cairo.line_to(ctx, pos[1], pos[2])
                stroke() # stroke after each segment
            end
        else
            if idx == 1
                Cairo.move_to(ctx, pos[1], pos[2])
            else
                Cairo.line_to(ctx, pos[1], pos[2])
                Cairo.move_to(ctx, pos[1], pos[2])
            end
        end
    end
    if idx == N && isa(primitive, Lines) # after adding all points, lines need a stroke
        stroke()
    end
end

function draw_segment(scene, ctx, point::Tuple{<: Point, <: Point}, model, c, linewidth, linestyle, primitive, idx, N)
    draw_segment(scene, ctx, point[1], model, c, linewidth, linestyle, primitive, 1 + (idx - 1) * 2, N)
    draw_segment(scene, ctx, point[2], model, c, linewidth, linestyle, primitive, (idx - 1) * 2, N)
end

function draw_atomic(scene::Scene, screen::CairoScreen, primitive::Union{Lines, LineSegments})
    fields = @get_attribute(primitive, (color, linewidth, linestyle))
    linestyle = AbstractPlotting.convert_attribute(linestyle, AbstractPlotting.key"linestyle"())
    ctx = screen.context
    model = primitive[:model][]
    positions = primitive[1][]
    isempty(positions) && return
    N = length(positions)
    if color isa AbstractArray{<: Number}
        color = AbstractPlotting.interpolated_getindex.((to_colormap(primitive.colormap[]),), color, (primitive.colorrange[],))
    end
    broadcast_foreach(1:N, positions, color, linewidth) do i, point, c, linewidth
        draw_segment(scene, ctx, point, model, c, linewidth, linestyle, primitive, i, N)
    end
    nothing
end

################################################################################
#                                   Scatter                                    #
################################################################################

function draw_marker(ctx, marker, pos, scale,
                    strokecolor, strokewidth, rotation,
                    mo, font
                )
    pos += Point2f0(scale[1] / 2, -scale[2] / 2)
    Cairo.arc(ctx, pos[1], pos[2], scale[1] / 2, 0, 2*pi)
    Cairo.fill(ctx)
    sc = to_color(strokecolor)
    if strokewidth > 0.0
        Cairo.set_source_rgba(ctx, red(sc), green(sc), blue(sc), alpha(sc))
        Cairo.set_line_width(ctx, Float64(strokewidth))
        Cairo.stroke(ctx)
    end
end

function draw_marker(ctx, marker::Char, pos, scale, strokecolor, strokewidth, rotation, mo, font)
    pos += Point2f0(scale[1] / 2, -scale[2] / 2)

    # Look for alternative fonts if the chosen font cannot support the marker.
    font = best_font(marker, font)

    # Set the font to the preferred one
    set_ft_font(ctx, font)

    mat = scale_matrix(scale...)
    set_font_matrix(ctx, mat)

    # Move to the marker position and rotate appropriately
    Cairo.translate(ctx, pos[1], pos[2])
    Cairo.rotate(ctx, -2acos(rotation[4]))

    # Construct a glyph to be placed
    glyph = CairoGlyph(font, marker)

    extent = glyph_extents(ctx, [glyph])

    w, h = extent[3:4]

    print("hi")

    Cairo.translate(ctx, -w/2, h/2)

    # Show the glyph
    show_glyphs(ctx, [glyph])

    if strokewidth > 0.0
        sc = to_color(strokecolor)
        Cairo.set_source_rgba(ctx, sc)
        Cairo.set_line_width(ctx, Float64(strokewidth))
        Cairo.text_path(ctx, marker_str)
        Cairo.stroke(ctx)
    end
end


function draw_marker(ctx, marker::Union{Rect, Type{<: Rect}}, pos, scale, strokecolor, strokewidth, rotation, mo, font)
    pos += Point2f0(mo[1], -mo[2])

    s2 = Point2f0(scale[1], -scale[2])

    Cairo.rotate(ctx, -2acos(rotation[4]))

    Cairo.rectangle(ctx, pos..., s2...)
    Cairo.fill(ctx);
    if strokewidth > 0.0
        sc = to_color(strokecolor)
        Cairo.set_source_rgba(ctx, red(sc), green(sc), blue(sc), alpha(sc))
        Cairo.set_line_width(ctx, Float64(strokewidth))
        Cairo.stroke(ctx)
    end
end

function draw_atomic(scene::Scene, screen::CairoScreen, primitive::Scatter)
    fields = @get_attribute(primitive, (color, markersize, strokecolor, strokewidth, marker, marker_offset, rotations))
    @get_attribute(primitive, (transform_marker,))

    cmap = get(primitive, :colormap, nothing) |> to_value |> to_colormap
    crange = get(primitive, :colorrange, nothing) |> to_value

    font = if marker isa Char
            if hasproperty(plot, :font)
                best_font(marker, plot.font[])
            else
                best_font(marker)
            end
        else
            nothing
        end

    ctx = screen.context
    model = primitive[:model][]
    positions = primitive[1][]
    isempty(positions) && return
    size_model = transform_marker ? model : Mat4f0(I)
    broadcast_foreach(primitive[1][], fields..., font) do point, c, markersize, strokecolor, strokewidth, marker, mo, rotation, font

        scale = project_scale(scene, markersize, size_model)

        pos = project_position(scene, point, model)

        mo = project_scale(scene, mo, size_model)

        Cairo.set_source_rgba(ctx, extract_color(cmap, crange, c)...)

        m = convert_attribute(marker, key"marker"(), key"scatter"())

        Cairo.save(ctx)

        draw_marker(ctx, m, pos, scale, strokecolor, strokewidth, rotation, mo, font)

        Cairo.restore(ctx)
    end
    nothing
end

################################################################################
#                                     Text                                     #
################################################################################

function draw_atomic(scene::Scene, screen::CairoScreen, primitive::Text)
    ctx = screen.context
    @get_attribute(primitive, (textsize, color, font, align, rotation, model))
    txt = to_value(primitive[1])
    position = primitive.attributes[:position][]

    N = length(txt)
    atlas = AbstractPlotting.get_texture_atlas()
    if position isa StaticArrays.StaticArray # one position to place text
        position, textsize = AbstractPlotting.layout_text(
            txt, position, textsize,
            font, align, rotation, model
        )
    end
    stridx = 1
    broadcast_foreach(1:N, position, textsize, color, font, rotation) do i, p, ts, cc, f, r
        Cairo.save(ctx)
        char = txt[stridx]
        stridx = nextind(txt, stridx)
        rels = to_rel_scale(atlas, char, f, ts)
        pos = project_position(scene, p, Mat4f0(I))
        Cairo.move_to(ctx, pos[1], pos[2])
        Cairo.set_source_rgba(ctx, red(cc), green(cc), blue(cc), alpha(cc))
        Cairo.select_font_face(
            ctx, fontname(f),
            Cairo.FONT_SLANT_NORMAL,
            Cairo.FONT_WEIGHT_NORMAL
        )
        #set_ft_font(ctx, f)
        ts = fontscale(atlas, scene, char, f, ts)
        mat = scale_matrix(ts...)
        set_font_matrix(ctx, mat)
        # set_font_size(ctx, 16)
        # TODO this only works in 2d
        Cairo.rotate(ctx, -2acos(r[4]))
        Cairo.show_text(ctx, string(char))
        Cairo.restore(ctx)
    end
    nothing
end

################################################################################
#                                Heatmap, Image                                #
################################################################################

function draw_atomic(scene::Scene, screen::CairoScreen, primitive::Union{Heatmap, Image})
    ctx = screen.context

    image = primitive[3][]
    x, y = primitive[1][], primitive[2][]

    model = primitive[:model][]

    imsize = (extrema_nan(x), extrema_nan(y))

    xy_ = project_position(scene, Point2f0(first.(imsize)), model)
    xymax_ = project_position(scene, Point2f0(last.(imsize)), model)
    xy = min.(xy_, xymax_)
    xymax = max.(xy_, xymax_)
    w, h = xymax .- xy

    interp = to_value(get(primitive, :interpolate, true))
    interp = interp ? Cairo.FILTER_BEST : Cairo.FILTER_NEAREST

    s = to_cairo_image(image, primitive)

    Cairo.rectangle(ctx, xy..., w, h)
    Cairo.save(ctx)

    Cairo.translate(ctx, xy[1], xy[2])
    Cairo.scale(ctx, w / s.width, h / s.height)

    Cairo.set_source_surface(ctx, s, 0, 0)

    p = Cairo.get_source(ctx)
    # Set filter doesn't work!?
    Cairo.pattern_set_filter(p, interp)
    Cairo.fill(ctx)

    Cairo.restore(ctx)
end

################################################################################
#                                     Mesh                                     #
################################################################################

function draw_atomic(scene::Scene, screen::CairoScreen, primitive::Mesh)
    @get_attribute(primitive, (color,))

    colormap = get(primitive, :colormap, nothing) |> to_value |> to_colormap
    colorrange = get(primitive, :colorrange, nothing) |> to_value

    ctx = screen.context
    model = primitive.model[]
    mesh = primitive[1][]
    vs = vertices(mesh); fs = faces(mesh)
    uv = hastexturecoordinates(mesh) ? texturecoordinates(mesh) : nothing
    pattern = Cairo.CairoPatternMesh()

    if mesh.attributes !== nothing && mesh.attribute_id !== nothing
        color = mesh.attributes[Int.(mesh.attribute_id .+ 1)]
    end

    cols = per_face_colors(color, colormap, colorrange, vs, fs, uv)

    for (f, (c1, c2, c3)) in zip(fs, cols)
        t1, t2, t3 =  project_position.(scene, vs[f], (model,)) #triangle points
        Cairo.mesh_pattern_begin_patch(pattern)

        Cairo.mesh_pattern_move_to(pattern, t1...)
        Cairo.mesh_pattern_line_to(pattern, t2...)
        Cairo.mesh_pattern_line_to(pattern, t3...)

        mesh_pattern_set_corner_color(pattern, 0, c1)
        mesh_pattern_set_corner_color(pattern, 1, c2)
        mesh_pattern_set_corner_color(pattern, 2, c3)

        Cairo.mesh_pattern_end_patch(pattern)
    end
    Cairo.set_source(ctx, pattern)
    Cairo.close_path(ctx)
    Cairo.paint(ctx)
    return nothing
end
