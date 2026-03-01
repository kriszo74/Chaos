# Önálló UnitRange demó közös positions_all vektorral.
# Több forrás egyetlen meshscatter! plottal jelenik meg.
# A források a közös tömbök szeleteit (start:stop) birtokolják.

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using Chaos
using GLMakie
using Colors

function source_uv(abscol::Int, cols::Int)
    u0 = Float32((abscol - 1) / cols)
    sx = 1f0 / Float32(cols)
    return Makie.uv_transform((Vec2f(0f0, u0 + sx / 2f0), Vec2f(1f0, 0f0)))
end

function allocate_source!(positions_all, radii_all, uv_all, n::Int; x0::Float32, dx::Float32, r::Float32, abscol::Int, cols::Int)
    start_ix = length(positions_all) + 1
    stop_ix = start_ix + n - 1
    rng = start_ix:stop_ix

    append!(positions_all, [Point3f(x0 + dx * k, 0f0, 0f0) for k in 0:n-1])
    append!(radii_all, fill(r, n))
    append!(uv_all, fill(source_uv(abscol, cols), n))

    return rng
end

function main()
    fig, scene = Chaos.setup_scene()
    marker = Chaos.create_detailed_sphere_fast(Point3f(0f0, 0f0, 0f0), 1f0, 48)

    colors = Matrix{RGBAf}(undef, 3, 3)
    colors[:, 1] = RGBAf[RGBAf(1f0, 0f0, 0f0, 1f0), RGBAf(1f0, 1f0, 1f0, 1f0), RGBAf(0f0, 0f0, 1f0, 1f0)]
    colors[:, 2] = RGBAf[RGBAf(0f0, 1f0, 0f0, 1f0), RGBAf(1f0, 1f0, 1f0, 1f0), RGBAf(1f0, 0f0, 1f0, 1f0)]
    colors[:, 3] = RGBAf[RGBAf(1f0, 1f0, 0f0, 1f0), RGBAf(1f0, 1f0, 1f0, 1f0), RGBAf(0f0, 1f0, 1f0, 1f0)]

    positions_all = Point3f[]
    radii_all = Float32[]
    uv_all = Any[]

    src1 = allocate_source!(positions_all, radii_all, uv_all, 5; x0 = -3.6f0, dx = 0.45f0, r = 0.12f0, abscol = 1, cols = 3)
    src2 = allocate_source!(positions_all, radii_all, uv_all, 5; x0 = -0.6f0, dx = 0.45f0, r = 0.18f0, abscol = 2, cols = 3)
    src3 = allocate_source!(positions_all, radii_all, uv_all, 5; x0 = 2.4f0, dx = 0.45f0, r = 0.24f0, abscol = 3, cols = 3)

    println("src1 range: ", src1)
    println("src2 range: ", src2)
    println("src3 range: ", src3)
    println("src2 positions slice: ", positions_all[src2])

    meshscatter!(
        scene,
        positions_all;
        marker = marker,
        markersize = radii_all,
        color = colors,
        uv_transform = uv_all,
        shading = true,
        transparency = false,
    )

    screen = display(fig)
    isinteractive() || wait(screen)
    return nothing
end

main()
