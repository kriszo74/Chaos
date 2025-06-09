using GLMakie
using StaticArrays

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

# Visszaállítjuk az eredeti iterátor logikát
Base.iterate(iter::ImpulzusIterátor, state=0) =
    state > iter.n_max ? nothing : begin
        t = iter.dt * state
        shift = SVector(iter.forrás.RV * t, 0.0, 0.0)  # mozgás X irányban
        pozíció = iter.forrás.pozíció0 + shift
        sugár = iter.forrás.RV * (iter.n_max * iter.dt - t)
        ((pozíció, sugár), state + 1)  # Most (pozíció, sugár) párt adunk vissza
    end

# --- Originális időforrás létrehozása ---
origin = Idoforras(SVector(0.0, 0.0, 0.0), 0.5, 0.0)  # például RV = 0.5
imp_iter = ImpulzusIterátor(origin, 0.05, 100)  # dt, lépésszám

# --- 3D Megjelenítés Beállítása ---
include("scene_setup.jl")
fig, scene = setup_scene(; use_axis3 = true)  # Itt lehet váltani true/false között

# Impulzushatárok - minden gömböt külön rajzolunk ki meshscatter!-rel
for (pos, r) in imp_iter
    meshscatter!(
        scene,
        [Point3f(pos...)],  # Egy elemű tömb
        markersize = [Float32(r)],  # Egy elemű tömb
        color = RGBf(0.6, 1.0, 1.0),
        transparency = true,
        alpha = 0.05,
        shading = NoShading
    )
end

# --- Vízvonal kirajzolása ---
dt = 0.05
steps = 100
pozíciók = [Point3f(origin.pozíció0[1] - origin.RV * dt * i, 0.0, 0.0) for i in 0:steps]
lines!(scene, pozíciók, color=:white, linewidth=1.5)

# --- Kamera automatikus illesztése vagy kézi limits beállítás ---
# autolimits!(scene)
# limits!(scene, FRect3D(Point3f(-1, -1, -1), Vec3f(2, 2, 2)))

fig