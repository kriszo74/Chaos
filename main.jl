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

Base.iterate(iter::ImpulzusIterátor, state=0) =
    state > iter.n_max ? nothing : begin
        t = iter.dt * state
        shift = SVector(iter.forrás.RV * t, 0.0, 0.0)  # mozgás X irányban
        pozíció = iter.forrás.pozíció0 + shift
        sugár = iter.forrás.RV * (iter.n_max * iter.dt - t)
        (Sphere(Point3f(pozíció...), sugár), state + 1)
    end

# --- Originális időforrás létrehozása ---
origin = Idoforras(SVector(0.0, 0.0, 0.0), 0.5, 0.0)  # például RV = 0.5
imp_iter = ImpulzusIterátor(origin, 0.05, 100)  # dt, lépésszám

# --- 3D megjelenítés ---
fig = Figure(backgroundcolor = RGBf(0.302, 0.322, 0.471))  # #4D5278
#scene = LScene(fig[1, 1], show_axis = false)
# ax = Axis3(fig[1, 1], aspect = :data, perspectiveness = 0.0, elevation = π/2,  azimuth = 3π/2, xgridvisible = ...,
scene = Axis3(fig[1, 1],
    aspect = :data,
    perspectiveness = 0.0,
    elevation = π/2,
    azimuth = 3π/2,
    xgridvisible = false,
    ygridvisible = false,
    zgridvisible = false,
    xspinesvisible = false,
    xlabelvisible = false,
    xticksvisible = false,
    xticklabelsvisible = false,
    yspinesvisible = false,
    ylabelvisible = false,
    yticksvisible = false,
    yticklabelsvisible = false,
    zspinesvisible = false,
    zlabelvisible = false,
    zticksvisible = false,
    zticklabelsvisible = false
)
#cam3d!(scene, projectiontype = :orthographic, eyeposition = Vec3f(0,0,4), lookat = Vec3f(0, 0, 0),upvector = Vec3f(0, 1, 0))

# Impulzushatárok
for g in imp_iter
    #@infiltrate
    mesh!(scene, g, color = (RGBf(0.6, 1.0, 1.0), 0.05), transparency=true)  # türkiz (#99FFFF), 0.05 áttetszőség
end

# --- Vízvonal kirajzolása ---
dt = 0.05
steps = 100
pozíciók = [Point3f(origin.pozíció0[1] - origin.RV * dt * i, 0.0, 0.0) for i in 0:steps]
#@infiltrate
lines!(scene, pozíciók, color=:white, linewidth=1.5)

# --- Kamera automatikus illesztése vagy kézi limits beállítás ---
# autolimits!(ax)  # automatikusan belenagyít az összes objektum alapján
# limits!(ax, FRect3D(Point3f(-1, -1, -1), Vec3f(2, 2, 2)))  # kézi bounding box, ha fix területet akarunk

fig