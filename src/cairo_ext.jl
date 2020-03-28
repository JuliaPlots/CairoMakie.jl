const LIB_CAIRO = if isdefined(Cairo, :libcairo)
    Cairo.libcairo
else
    Cairo._jl_libcairo
end
function set_font_matrix(cr, matrix)
    ccall((:cairo_set_font_matrix, LIB_CAIRO), Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}), cr.ptr, Ref(matrix))
end

"""
Finds a font that can represent the unicode character!
Returns AbstractPlotting.defaultfont() if not representable!
"""
function best_font(c::Char)
    font = AbstractPlotting.defaultfont()
    if FreeType.FT_Get_Char_Index(font, c) == 0
        for afont in AbstractPlotting.alternativefonts()
            if FreeType.FT_Get_Char_Index(afont, c) != 0
                return afont
            end
        end
    end
    @debug "Unable to represent glyph '$c' in AbstractPlotting fonts."
    return font
end

function best_font(char::Char, font::FreeTypeAbstraction.FTFont)
    # If the font cannot represent the character, look for alternatives
    if FreeType.FT_Get_Char_Index(font, char) == 0
        return best_font(char)
    end
    # If we get here, the font can represent the character
    return font
end

best_font(char::Char, ::Nothing) = best_font(char)

function set_ft_font(cr, font::FreeTypeAbstraction.FTFont)
    font_face = ccall(
        (:cairo_ft_font_face_create_for_ft_face, LIB_CAIRO),
        Ptr{Cvoid}, (FreeTypeAbstraction.FT_Face, Cint),
        font, 0
    )
    ccall((:cairo_set_font_face, LIB_CAIRO), Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}), cr.ptr, font_face)
end


function rot_scale_trans_matrix(x, y, r, offset)
    matrix = Ref(scale_matrix(x, y))
    ccall((:cairo_matrix_translate, LIB_CAIRO), Cvoid, (Ptr{Cvoid}, Float64, Float64), matrix, offset[1], offset[2])
    ccall((:cairo_matrix_rotate, LIB_CAIRO), Cvoid, (Ptr{Cvoid}, Float64), matrix, r)
    return matrix[]
end


struct CairoGlyph
    index::Culong
    x::Float64
    y::Float64
end

function CairoGlyph(font::FreeTypeAbstraction.FTFont, char::Char, x=0.0, y=0.0)
    idx = FreeType.FT_Get_Char_Index(font, char)
    return CairoGlyph(Culong(char), x, y)
end

function show_glyphs(ctx, glyphs::Vector{CairoGlyph})
    ccall((:cairo_show_glyphs, CairoMakie.LIB_CAIRO),
          Cvoid, (Ptr{Cvoid}, Ptr{CairoGlyph}, Cint),
          ctx.ptr, glyphs, length(glyphs))
end

function glyph_extents(ctx, glyphs::Vector{CairoGlyph})
    extents = Matrix{Float64}(undef, 6, 1)
    ccall((:cairo_glyph_extents, CairoMakie.LIB_CAIRO),
          Cvoid, (Ptr{Cvoid}, Ptr{CairoGlyph}, Cint, Ptr{Float64}),
          ctx.ptr, glyphs, length(glyphs), extents)
    return extents
end
