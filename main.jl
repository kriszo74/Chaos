using GLMakie
using StaticArrays
using GeometryBasics

# --- Időforrás definíció ---
struct Idoforras
    pozíció0::SVector{3, Float64}  # originális kezdőpozíció
    RV::Float64                    # múlttérterjedési sebesség
    t0::Float64                    # kiáradás kezdőideje (pl. 0.0)
end

# --- Impulzus iterátor: mozgó forrásból generál gömböket ---
struct ImpulzusIterátor
    forrás::Idoforras
    dt::Float64
    n_max::Int
end

# Gömbfelület egyetlen hívással (GeometryBasics helper)
function create_detailed_sphere(center::Point3f, radius::Float32, res::Int = 48)
    sp     = Sphere(center, radius)               # beépített típus
    verts  = GeometryBasics.coordinates(sp, res)  # res×res pont
    idxs   = GeometryBasics.faces(sp, res)
    return GeometryBasics.Mesh(verts, idxs)
end

# Iterátor logika
Base.iterate(iter::ImpulzusIterátor, state=0) =
    state > iter.n_max ? nothing : begin
        t        = iter.dt * state
        shift    = SVector(iter.forrás.RV * t, 0.0, 0.0)   # mozgás X‑irányban
        pozíció  = iter.forrás.pozíció0 + shift
        sugár    = iter.forrás.RV * (iter.n_max * iter.dt - t)
        ((pozíció, sugár), state + 1)
    end

# --- Eredeti időforrás ---
origin   = Idoforras(SVector(0.0, 0.0, 0.0), 0.5, 0.0)
imp_iter = ImpulzusIterátor(origin, 0.05, 100)

# --- Megjelenítés ---
include("scene_setup.jl")
fig, scene = setup_scene(; use_axis3 = true)


# --- Gömbhéjak kirajzolása ---
for (pos, r) in imp_iter
    meshscatter!(
        scene,
        [Point3f(pos...)],
        marker      = create_detailed_sphere(Point3f(0, 0, 0), 1f0, 48),
        markersize  = Float32(r),
        color       = RGBf(0.6, 1.0, 1.0),
        transparency = true,
        alpha        = 0.05,
        shading      = NoShading,
    )
end

# --- Vízvonal ---
dt = 0.05; steps = 100
pozíciók = [Point3f(origin.pozíció0[1] - origin.RV * dt * i, 0.0, 0.0) for i in 0:steps]
lines!(scene, pozíciók, color = :white, linewidth = 1.5)

fig
