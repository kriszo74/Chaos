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
# Jelenet (Scene) létrehozása háttérszínnel – mindig LScene, ortografikus kamera
# -----------------------------------------------------------------------------
function setup_scene(; backgroundcolor = RGBf(0.302, 0.322, 0.471))
    fig = Figure(sizeof = (600, 450), backgroundcolor = backgroundcolor, figure_padding = 0)
    scene = LScene(fig[1, 1], show_axis = false)
    cam3d!(scene; projectiontype = :orthographic,
            eyeposition  = Vec3f(0, 0, 1),
            lookat       = Vec3f(0, 0, 0),
            upvector     = Vec3f(0,  1, 0))
    return fig, scene
end

