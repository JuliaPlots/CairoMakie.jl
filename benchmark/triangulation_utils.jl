"""
    grid_triangle_faces(lats, lons)

Returns a series of triangle indices from naive triangulation.
"""
function grid_triangle_faces(lons, lats)
    faces = Array{Int, 2}(undef, (length(lons)-1)*(length(lats)-1)*2, 3)

    xmax = length(lons)

    i = 1
    # TODO optimize this with broadcast
    for lon in eachindex(lons)[1:end-1]

        for lat in eachindex(lats)[1:end-1]

            cpos = lon + (lat-1)*xmax

            faces[i, :] = [cpos, cpos+1, cpos+xmax+1]

            faces[i+1, :] = [cpos, cpos+xmax, cpos+xmax+1]

            i += 2

        end
    end

    return faces

end

"""
    gridpoints(xs, ys)

Returns a Vector of Points of a grid formed by xs and ys.
"""
gridpoints(xs, ys) = vec([Point2f0(x, y) for y in ys, x in xs])

"""
    triangulated_grid(xs, ys) -> points, faces

Takes in two ranges, and returns a triangulated regular grid based on those ranges.
"""
triangulated_grid(xs, ys) = (gridpoints(xs, ys), grid_triangle_faces(xs, ys))
