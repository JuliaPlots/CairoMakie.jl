################################################################################
#                            General font handling                             #
################################################################################

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

"""
Finds a font that can represent the unicode character!
Returns AbstractPlotting.defaultfont() if not representable!
"""
function best_font(c::Char, font = AbstractPlotting.defaultfont())
    if AbstractPlotting.FreeType.FT_Get_Char_Index(font, c) == 0
        for afont in AbstractPlotting.alternativefonts()
            if AbstractPlotting.FreeType.FT_Get_Char_Index(afont, c) != 0
                return afont
            end
        end
        return AbstractPlotting.defaultfont()
    end
    return font
end

################################################################################
#                                Glyph handling                                #
################################################################################

function glyph_index(char::Char, font::AbstractPlotting.FreeTypeAbstraction.FTFont)
    return AbstractPlotting.FreeType.FT_Get_Char_Index(font, Culong(char))
end

"""
    CairoGlyph(index, x, y)
    CairoGlyph(char, font, [x = 0.0, y = 0.0])

Constructs a glyph type for Cairo, which stores an index and an offset.
"""
struct CairoGlyph
    "The index of the character in its font"
    index::Culong
    """
    The offset in the X direction between the origin used for drawing or
    measuring the string and the origin of this glyph.
    """
    x::Cdouble
    """
    the offset in the Y direction between the origin used for drawing or
    measuring the string and the origin of this glyph.
    """
    y::Cdouble
end

function CairoGlyph(
        char::Char, font::AbstractPlotting.FreeTypeAbstraction.FTFont,
        x::Float64 = 0.0, y::Float64 = 0.0
    )
    return CairoGlyph(glyph_index(char, font), x, y)
end

function show_glyphs(ctx::Cairo.CairoContext, glyphs::Vector{CairoGlyph})
    return ccall(
        (:cairo_show_glyphs, LIB_CAIRO),
        Cvoid,
        (Ptr{Cvoid}, Ptr{CairoGlyph}, Cint),
        ctx.ptr, glyphs, length(glyphs)
    )
end

function glyph_path(ctx::Cairo.CairoContext, glyphs::Vector{CairoGlyph})
    return ccall(
        (:cairo_glyph_path, LIB_CAIRO),
        Cvoid,
        (Ptr{Cvoid}, Ptr{CairoGlyph}, Cint),
        ctx.ptr, glyphs, length(glyphs)
    )
end
