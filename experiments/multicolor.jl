# Önállóan futtatható meshscatter teszt 5 gömbbel.
# A marker create_detailed_sphere_fast alapján készül.
# Növekvő gömbsorozatot rajzol külön színekkel.

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using Chaos
using GLMakie
using Colors

function main()
    fig, scene = Chaos.setup_scene()
    marker = Chaos.create_detailed_sphere_fast(Point3f(0f0, 0f0, 0f0), 1f0, 48)

    positions = [Point3f(0.0f0 + 1.3f0 * i, 0.0f0, 0.0f0) for i in 0:4]
    radii = Float32[0.18, 0.28, 0.38, 0.48, 0.58]

# homogén szinek vektor
#=     colors = RGBAf[
        RGBAf(1f0, 0f0, 0f0, 1f0),
        RGBAf(1f0, 0.5f0, 0f0, 1f0),
        RGBAf(1f0, 1f0, 0f0, 1f0),
        RGBAf(0f0, 1f0, 0f0, 1f0),
        RGBAf(0f0, 0.6f0, 1f0, 1f0),
    ]
 =#    
    
 # atlasz + uv_transforms
    colors = Matrix{RGBAf}(undef, 3, 5)
    colors[:, 1] = RGBAf[RGBAf(1f0, 0f0, 0f0, 1f0), RGBAf(1f0, 1f0, 1f0, 1f0), RGBAf(0f0, 0f0, 1f0, 1f0)]
    colors[:, 2] = RGBAf[RGBAf(0f0, 1f0, 0f0, 1f0), RGBAf(1f0, 1f0, 1f0, 1f0), RGBAf(1f0, 0f0, 1f0, 1f0)]
    colors[:, 3] = RGBAf[RGBAf(1f0, 1f0, 0f0, 1f0), RGBAf(1f0, 1f0, 1f0, 1f0), RGBAf(0f0, 1f0, 1f0, 1f0)]
    colors[:, 4] = RGBAf[RGBAf(1f0, 0.5f0, 0f0, 1f0), RGBAf(1f0, 1f0, 1f0, 1f0), RGBAf(0.5f0, 0f0, 1f0, 1f0)]
    colors[:, 5] = RGBAf[RGBAf(0f0, 0.7f0, 1f0, 1f0), RGBAf(1f0, 1f0, 1f0, 1f0), RGBAf(1f0, 0.2f0, 0.2f0, 1f0)]
    uv_transforms = [Makie.uv_transform((Vec2f(0f0, (i - 0.5f0) / 5f0), Vec2f(1f0, 0f0))) for i in 1:5]

    meshscatter!(
        scene,
        positions;
        marker = marker,
        markersize = radii,
        color = colors,
        uv_transform = uv_transforms,
        shading = true,
        transparency = false,
    )

    screen = display(fig)
    isinteractive() || wait(screen)
    return nothing
end

main()
