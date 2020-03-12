Cairo.set_source_rgba(ctx, c::Colors.RGBA) = Cairo.set_source_rgba(ctx, red(c), green(c), blue(c), alpha(c))

Cairo.set_source_rgb(ctx, c::Colors.AbstractRGB) = Cairo.set_source_rgb(ctx, red(c), green(c), blue(c))
