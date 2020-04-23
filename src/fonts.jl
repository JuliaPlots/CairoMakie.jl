
function set_font_matrix(cr, matrix)
    ccall((:cairo_set_font_matrix, LIB_CAIRO), Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}), cr.ptr, Ref(matrix))
end

function set_ft_font(cr, font)
    font_face = ccall(
        (:cairo_ft_font_face_create_for_ft_face, LIB_CAIRO),
        Ptr{Cvoid}, (AbstractPlotting.FreeTypeAbstraction.FT_Face, Cint),
        font, 0
    )
    ccall((:cairo_set_font_face, LIB_CAIRO), Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}), cr.ptr, font_face)
    font_face
end

function cairo_font_face_destroy(font_face)
    ccall(
        (:cairo_font_face_destroy, LIB_CAIRO),
        Cvoid, (Ptr{Cvoid},),
        font_face
    )
end

fontname(x::String) = x
fontname(x::Symbol) = string(x)
function fontname(x::NativeFont)
    return x.family_name
end
