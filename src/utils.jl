################################################################################
#                             Projection utilities                             #
################################################################################


function project_position(scene, point, model)
    res = scene.camera.resolution[]
    p4d = to_ndim(Vec4f0, to_ndim(Vec3f0, point, 0f0), 1f0)
    clip = scene.camera.projectionview[] * model * p4d
    @inbounds begin
    # between -1 and 1
        p = (clip ./ clip[4])[Vec(1, 2)]
        # flip y to match cairo
        p_yflip = Vec2f0(p[1], -p[2])
        # normalize to between 0 and 1
        p_0_to_1 = (p_yflip .+ 1f0) / 2f0
    end
    # multiply with scene resolution for final position
    return p_0_to_1 .* res
end

project_scale(scene::Scene, s::Number, model = Mat4f0(I)) = project_scale(scene, Vec2f0(s), model)

function project_scale(scene::Scene, s, model = Mat4f0(I))
    p4d = to_ndim(Vec4f0, s, 0f0)
    p = @inbounds (scene.camera.projectionview[] * model * p4d)[Vec(1, 2)] ./ 2f0
    return p .* scene.camera.resolution[]
end

function project_rect(scene, rect::Rect, model)
    mini = project_position(scene, minimum(rect), model)
    maxi = project_position(scene, maximum(rect), model)
    return Rect(mini, maxi .- mini)
end

########################################
#          Rotation handling           #
########################################

function to_2d_rotation(::T) where T
    error("Type $T cannot be converted to a 2D rotation")
end

to_2d_rotation(quat::AbstractPlotting.Quaternion) = -AbstractPlotting.quaternion_to_2d_angle(quat)

to_2d_rotation(vec::Vec2f0) = (atan(-vec[2], vec[1]))

to_2d_rotation(n::Real) = n


################################################################################
#                                Color handling                                #
################################################################################

function rgbatuple(c::Colorant)
    rgba = RGBA(c)
    red(rgba), green(rgba), blue(rgba), alpha(rgba)
end

rgbatuple(c) = rgbatuple(to_color(c))


function numbers_to_colors(numbers::AbstractArray{<:Number}, primitive)

    colormap = get(primitive, :colormap, nothing) |> to_value |> to_colormap
    colorrange = get(primitive, :colorrange, nothing) |> to_value

    if colorrange === AbstractPlotting.automatic
        colorrange = extrema(numbers)
    end

    AbstractPlotting.interpolated_getindex.(
        Ref(colormap),
        Float64.(numbers), # ints don't work in interpolated_getindex
        Ref(colorrange))
end

to_uint32_color(c) = reinterpret(UInt32, convert(ARGB32, c))

########################################
#            Image handling            #
########################################

function to_cairo_image(img::Matrix{UInt32}, attributes)
    @inbounds CairoARGBSurface(
        [
            img[j, i]
            for i in size(img, 2):-1:1, # account for Y-axis discrepancy in Cairo
                j in 1:size(img, 1)
        ]
    )
end

function to_cairo_image(img, attributes)
    @inbounds to_cairo_image(to_uint32_color.(img), attributes)
end


function to_cairo_image(img::AbstractMatrix{<: AbstractFloat}, attributes)
    imui32 = to_uint32_color.(numbers_to_colors(img, attributes))
    to_cairo_image(imui32, attributes)
end

################################################################################
#                           Mesh handling for Cairo                            #
################################################################################

struct FaceIterator{Iteration, T, F, ET} <: AbstractVector{ET}
    data::T
    faces::F
end

function (::Type{FaceIterator{Typ}})(data::T, faces::F) where {Typ, T, F}
    FaceIterator{Typ, T, F}(data, faces)
end
function (::Type{FaceIterator{Typ, T, F}})(data::AbstractVector, faces::F) where {Typ, F, T}
    FaceIterator{Typ, T, F, NTuple{3, eltype(data)}}(data, faces)
end
function (::Type{FaceIterator{Typ, T, F}})(data::T, faces::F) where {Typ, T, F}
    FaceIterator{Typ, T, F, NTuple{3, T}}(data, faces)
end
function FaceIterator(data::AbstractVector, faces)
    if length(data) == length(faces)
        FaceIterator{:PerFace}(data, faces)
    else
        FaceIterator{:PerVert}(data, faces)
    end
end


Base.size(fi::FaceIterator) = size(fi.faces)
Base.getindex(fi::FaceIterator{:PerFace}, i::Integer) = fi.data[i]
Base.getindex(fi::FaceIterator{:PerVert}, i::Integer) = fi.data[fi.faces[i]]
Base.getindex(fi::FaceIterator{:Const}, i::Integer) = ntuple(i-> fi.data, 3)

function per_face_colors(color, colormap, colorrange, vertices, faces, uv)
    if color isa Colorant
        return FaceIterator{:Const}(color, faces)
    elseif color isa AbstractArray
        if color isa AbstractVector{<: Colorant}
            return FaceIterator(color, faces)
        elseif color isa AbstractVector{<: Number}
            cvec = AbstractPlotting.interpolated_getindex.((colormap,), color, (colorrange,))
            return FaceIterator(cvec, faces)
        elseif color isa AbstractMatrix{<: Colorant} && uv !== nothing
            cvec = map(uv) do uv
                wsize = reverse(size(color))
                wh = wsize .- 1
                x, y = round.(Int, Tuple(uv) .* wh) .+ 1
                return color[size(color, 1) - (y - 1), x]
            end
            # TODO This is wrong and doesn't actually interpolate
            # Inside the triangle sampling the color image
            return FaceIterator(cvec, faces)
        end
    end
    error("Unsupported Color type: $(typeof(color))")
end

mesh_pattern_set_corner_color(pattern, id, c) =
    Cairo.mesh_pattern_set_corner_color_rgba(pattern, id, rgbatuple(c)...)

################################################################################
#                            Tagging infrastructure                            #
################################################################################

function begin_tag(ctx, tagname::String, metadata::String)
    ccall(
        (:cairo_tag_begin, LIB_CAIRO),
        Cvoid,
        (Ptr{Cairo.CairoContext}, Ptr{Cchar}, Ptr{Cchar}),
        ctx.ptr, tagname, metadata
    )
end

function end_tag(ctx, tagname::String)
    ccall(
        (:cairo_tag_end, LIB_CAIRO),
        Cvoid,
        (Ptr{Cairo.CairoContext}, Ptr{Cchar}),
        ctx.ptr, tagname
    )
end

"""
The attributes string is of the form "key1=value2 key2=value2 ...". Values may be boolean (true/false or 1/0), integer, float, string, or an array.

String values are enclosed in single quotes ('). Single quotes and backslashes inside the string should be escaped with a backslash.

Boolean values may be set to true by only specifying the key. eg the attribute string "key" is the equivalent to "key=true".

Arrays are enclosed in '[]'. eg "rect=[1.2 4.3 2.0 3.0]".

If no attributes are required, attributes can be an empty string or NULL.

See Tags and Links Description for the list of tags and attributes.
"""
function with_tag(f::Function, ctx::Cairo.CairoContext, tagname::String, metadata::String = "")
    begin_tag(ctx, tagname, metadata)
    f()
    end_tag(ctx, tagname)
end
