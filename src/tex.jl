using Rsvg, Cairo

function implant_math(str)
    """
    \\RequirePackage{luatex85}
    \\documentclass[preview, tightpage]{standalone}

    \\usepackage{amsmath, xcolor}
    \\pagestyle{empty}
    \\begin{document}
    \\($str\\)
    \\end{document}
    """
end

function latex2dvi(
        document::AbstractString;
        tex_engine = `lualatex`,
        options = `-halt-on-error`
    )
    return mktempdir() do dir

        # dir=mktempdir()
        # Begin by compiling the latex in a temp directory
        # Unfortunately for us, Luatex does not like to compile
        # straight to stdout; it really wants a filename.
        # We make a temporary directory for it to output to.
        latex = open(`$tex_engine $options -output-directory=$dir -output-format=dvi -jobname=temp`, "r+")
        print(latex, document) # print the TeX document to stdin
        close(latex.in)      # close the file descriptor to let LaTeX know we're done
        @show success(latex)
        @show readdir(dir)

        # We want to keep file writes to a minimum.  Everything should stay in memory.
        # Therefore, we exit the directory at this point, so that all auxiliary files
        # can be deleted.
        return read(joinpath(dir, "temp.dvi"))

    end
end

function dvi2svg(
        dvi::Vector{UInt8};
        bbox = "min", # minimal bounding box
        options = `--libgs=/usr/local/lib/libgs.so.9`
    )
    # dvisvgm will allow us to convert the DVI file into an SVG which
    # can be rendered by Rsvg.  In this case, we are able to provide
    # dvisvgm a DVI file from stdin, and receive a SVG string from
    # stdout.  This greatly simplifies the pipeline, and anyone with
    # a working TeX installation should have these utilities available.
    dvisvgm = open(`dvisvgm --bbox=$bbox $options --no-fonts  --stdin --stdout`, "r+")

    write(dvisvgm, dvi)

    close(dvisvgm.in)

    return read(dvisvgm.out, String) # read the SVG in as a String
end

function dvi2png(dvi::Vector{UInt8}; dpi = 3000.0)

    # dvisvgm will allow us to convert the DVI file into an SVG which
    # can be rendered by Rsvg.  In this case, we are able to provide
    # dvisvgm a DVI file from stdin, and receive a SVG string from
    # stdout.  This greatly simplifies the pipeline, and anyone with
    # a working TeX installation should have these utilities available.
    dvipng = open(`dvipng --bbox=$bbox $options --no-fonts  --stdin --stdout`, "r+")

    write(dvipng, dvi)

    close(dvipng.in)

    return read(dvipng.out, String) # read the SVG in as a String
end

function svg2img(svg::String; dpi = 3000.0)

    # First, we instantiate an Rsvg handle, which holds a parsed representation of
    # the SVG.  Then, we set its DPI to the provided DPI (usually, 300 is good).
    handle = Rsvg.handle_new_from_data(svg)
    Rsvg.handle_set_dpi(handle, dpi)

    # We can find the final dimensions (in pixel units) of the Rsvg image.
    # Then, it's possible to store the image in a native Julia array,
    # which simplifies the process of rendering.
    d = Rsvg.handle_get_dimensions(handle)
    @show d
    w, h = d.width, d.height
    img = Matrix{AbstractPlotting.Colors.ARGB32}(undef, w, h)

    # Cairo allows you to use a Matrix of ARGB32, which simplifies rendering.
    cs = Cairo.CairoImageSurface(img)
    c = Cairo.CairoContext(cs)

    # Render the parsed SVG to a Cairo context
    Rsvg.handle_render_cairo(c, handle)

    # The image is rendered transposed, so we need to flip it.
    return rotr90(Base.transpose(img))
end

function svg2rsvg(svg::String; dpi = 72.0)
    handle = Rsvg.handle_new_from_data(svg)
    Rsvg.handle_set_dpi(handle, dpi)
    return handle
end

function rsvg2recordsurf(handle::Rsvg.RsvgHandle)
    surf = Cairo.CairoRecordingSurface()
    ctx  = Cairo.CairoContext(surf)
    Rsvg.handle_render_cairo(ctx, handle)
    return (surf, ctx)
end

function render_surface(ctx::CairoContext, surf)
    Cairo.save(ctx)

    Cairo.set_source(ctx, surf, 0.0, 0.0)

    Cairo.paint(ctx)

    Cairo.restore(ctx)
    return
end

@recipe(TeXImg, origin, tex) do scene
    merge(
        default_theme(scene),
        Attributes(
            color = AbstractPlotting.automatic,
            implant = true
        )
    )
end

function AbstractPlotting.plot!(img::T) where T <: TeXImg

    pos = img[1][]
    tex = img[2][]
    str = if img.implant[]
        implant_math(tex)
    else
        tex
    end

    svg = dvi2svg(latex2dvi(str))

    png = svg2img(svg)

    image!(img, png)
end

function get_ink_extents(surf::CairoSurface)
    x0 = [0.0]
    y0 = [0.0]
    w  = [0.0]
    h  = [0.0]

    ccall(
        (:cairo_recording_surface_ink_extents, LIB_CAIRO),
        Cvoid,
        (Ptr{Cvoid}, Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}),
        surf.ptr, x0, y0, w, h
    )

    return (x0[1], y0[1], w[1], h[1])
end

function draw_plot(scene::Scene, screen::CairoScreen, img::TeXImg)

    bbox = AbstractPlotting.boundingbox(img)

    ctx = screen.context

    pos = img[1][]
    tex = img[2][]
    str = if img.implant[]
        implant_math(tex)
    else
        tex
    end

    pos = project_position(scene, pos, img.model[])

    svg = dvi2svg(latex2dvi(str))
    surf, cr = rsvg2recordsurf(svg2rsvg(svg))

    x0, y0, w, h = get_ink_extents(surf)

    @show((x0, y0, w, h))

    scale_factor = project_position(scene, widths(bbox), img.model[])

    @show scale_factor
    Cairo.save(ctx)
    Cairo.translate(ctx, pos[1], pos[2] - (h + y0) * scale_factor[2] / w)
    Cairo.scale(ctx, scale_factor[2] / w, scale_factor[2] / w)
    render_surface(ctx, surf)
    Cairo.restore(ctx)
end

export dvi2svg, latex2dvi, rsvg2recordsurf, svg2rsvg
