
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

scale_matrix(x, y) = Cairo.CairoMatrix(x, 0.0, 0.0, y, 0.0, 0.0)


"""
Finds a font that can represent the unicode character!
Returns AbstractPlotting.defaultfont() if not representable!
"""
function best_font(c::Char, font = AbstractPlotting.defaultfont())
    if FreeType.FT_Get_Char_Index(font, c) == 0
        for afont in AbstractPlotting.alternativefonts()
            if FreeType.FT_Get_Char_Index(afont, c) != 0
                return afont
            end
        end
        return AbstractPlotting.defaultfont()
    end
    return font
end
