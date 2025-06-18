# ---- 3dtools.jl ----

# Gömbfelület generálása egyetlen hívással (GeometryBasics helper)
# center  – a gömb közepe
# radius  – sugár
# res     – θ és φ irányú felbontás (≥ 3)
function create_detailed_sphere(center::Point3f, radius::Float32, res::Int = 48)
    sp     = Sphere(center, radius)               # beépített primitív
    verts  = GeometryBasics.coordinates(sp, res)  # res×res pont
    idxs   = GeometryBasics.faces(sp, res)        # indexlista
    return GeometryBasics.Mesh(verts, idxs)
end

# -----------------------------------------------------------------------------
# Jelenet (Scene) létrehozása – háttérszínnel, opcionális Axis3-mal
# -----------------------------------------------------------------------------
function setup_scene(; backgroundcolor = RGBf(0.302, 0.322, 0.471), use_axis3 = true)
    fig = Figure(backgroundcolor = backgroundcolor)  # fő figura

    if use_axis3
        scene = Axis3(fig[1, 1],
            aspect          = :data,
            perspectiveness = 0.0,
            elevation       = π/2,
            azimuth         = 3π/2,
            xgridvisible    = false, ygridvisible = false, zgridvisible = false,
            xspinesvisible  = false, xlabelvisible = false, xticksvisible = false, xticklabelsvisible = false,
            yspinesvisible  = false, ylabelvisible = false, yticksvisible = false, yticklabelsvisible = false,
            zspinesvisible  = false, zlabelvisible = false, zticksvisible = false, zticklabelsvisible = false,
        )
    else
        scene = LScene(fig[1, 1], show_axis = false)
        cam3d!(scene; projectiontype = :orthographic,
                eyeposition  = Vec3f(0, 0, 4),
                lookat       = Vec3f(0, 0, 0),
                upvector     = Vec3f(0, 1, 0))
    end

    return fig, scene
end

# -----------------------------------------------------------------------------
# Gömb animációs segédfüggvény: növekvő sugár
# -----------------------------------------------------------------------------
function animate_growing_sphere()
    fig, scene = setup_scene()
    pos  = Node(Point3f0(0))
    rad  = Node(0f0)
    sp   = create_detailed_sphere(Point3f(0, 0, 0), 1f0, 48)

    mesh!(scene, sp;
        scale = rad, translation = pos,
        color = RGBAf0(0.6, 1, 1, 0.3), shading = NoShading)

    @async begin
        t  = 0f0
        dt = 0.02f0
        c  = 0.5f0
        while isopen(fig.scene)
            t += dt
            rad[] = t * c
            sleep(dt)
        end
    end

    return fig
end
