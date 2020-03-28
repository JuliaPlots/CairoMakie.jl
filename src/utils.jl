################################################################################
#                                  Projection                                  #
################################################################################

function project_position(scene, point, model)
    res = scene.camera.resolution[]
    p4d = to_ndim(Vec4f0, to_ndim(Vec3f0, point, 0f0), 1f0)
    clip = scene.camera.projectionview[] * model * p4d
    p = (clip ./ clip[4])[Vec(1, 2)]
    p = Vec2f0(p[1], -p[2])
    ((((p .+ 1f0) / 2f0) .* (res .- 1f0)) .+ 1f0)
end

project_scale(scene::Scene, s::Number, model = Mat4f0(I)) = project_scale(scene, Vec2f0(s), model)

function project_scale(scene::Scene, s, model = Mat4f0(I))
    p4d = to_ndim(Vec4f0, s, 0f0)
    p = (scene.camera.projectionview[] * model * p4d)[Vec(1, 2)] ./ 2f0
    p .* scene.camera.resolution[]
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

################################################################################
#                                Font utilities                                #
################################################################################

fontname(x::String) = x
fontname(x::Symbol) = string(x)
function fontname(x::NativeFont)
    return x.family_name
end

function fontscale(atlas, scene, c, font, s)
    s = (s ./ atlas.scale[AbstractPlotting.glyph_index!(atlas, c, font)]) ./ 0.02
    project_scale(scene, s)
end

function to_rel_scale(atlas, c, font, scale)
    gs = atlas.scale[AbstractPlotting.glyph_index!(atlas, c, font)]
    (scale ./ 0.02) ./ gs
end

################################################################################
#                               Color utilities                                #
################################################################################

function color2tuple3(c)
    (red(c), green(c), blue(c))
end
function colorant2tuple4(c)
    (red(c), green(c), blue(c), alpha(c))
end

# TODO replace this with a Base.convert overload
to_uint32_color(c) = reinterpret(UInt32, convert(ARGB32, c))

_extract_color(cmap, range, c) = to_color(c)
_extract_color(cmap, range, c::RGBf0) = RGBAf0(c, 1.0)
_extract_color(cmap, range, c::RGBAf0) = c
function _extract_color(cmap, range, c::Number)
    AbstractPlotting.interpolated_getindex(cmap, c, range)
end
function extract_color(cmap, range, c)
    c = _extract_color(cmap, range, c)
    red(c), green(c), blue(c), alpha(c)
end

################################################################################
#                            Mesh drawing utilities                            #
################################################################################

########################################
#          Mesh face iterator          #
########################################

struct FaceIterator{Iteration, T, F, ET} <: AbstractVector{ET}
    data::T
    faces::F
end

function FaceIterator{Typ}(data::T, faces::F) where {Typ, T, F}
    FaceIterator{Typ, T, F}(data, faces)
end
function FaceIterator{Typ, T, F}(data::AbstractVector, faces::F) where {Typ, F, T}
    FaceIterator{Typ, T, F, NTuple{3, eltype(data)}}(data, faces)
end
function FaceIterator{Typ, T, F}(data::T, faces::F) where {Typ, T, F}
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

########################################
#          Mesh color setters          #
########################################

mesh_pattern_set_corner_color(pattern, id, c::Color3) =
    Cairo.mesh_pattern_set_corner_color_rgb(pattern, id, color2tuple3(c)...)
mesh_pattern_set_corner_color(pattern, id, c::Colorant{T,4} where T) =
    Cairo.mesh_pattern_set_corner_color_rgba(pattern, id, colorant2tuple4(c)...)

################################################################################
#                               Image conversion                               #
################################################################################


function to_cairo_image(img::AbstractMatrix{<: AbstractFloat}, attributes)
    AbstractPlotting.@get_attribute attributes (colormap, colorrange)
    imui32 = to_uint32_color.(AbstractPlotting.interpolated_getindex.(Ref(colormap), img, (colorrange,)))
    to_cairo_image(imui32, attributes)
end

function to_cairo_image(img::Matrix{UInt32}, attributes)
    CairoARGBSurface([img[j, i] for i in size(img, 2):-1:1, j in 1:size(img, 1)])
end

function to_cairo_image(img, attributes)
    to_cairo_image(to_uint32_color.(img), attributes)
end
