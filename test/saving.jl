database = MakieGallery.load_database(["short_tests.jl"]);

filter!(database) do example
    !("3d" ∈ example.tags)
end

format_save_path = joinpath(@__DIR__, "test_formats")
available_formats = ("png", "pdf", "jpeg", "svg", "eps")

isdir(format_save_path) && rm(format_save_path, recursive = true)
mkpath(format_save_path)

mkpath.(joinpath.(format_save_path, available_formats))

savepath(uid, fmt) = joinpath(format_save_path, fmt, "$uid.$fmt")

@testset "Saving formats" begin
    for fmt in available_formats
        for example in database
            @test try
                save(savepath(example.unique_name, fmt), MakieGallery.eval_example(example))
                true
            catch e
                @warn "Saving $(example.unique_name) in format `$fmt` failed!" exception=(e, Base.catch_backtrace())
                false
            end
        end
    end
end
