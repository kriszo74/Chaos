# ---- main.jl ----
using GLMakie
using StaticArrays
using GeometryBasics

# --- TimeSource (Időforrás) definíció ---
struct TimeSource
    position0::SVector{3, Float64}  # eredeti (kezdeti) pozíció
    speed::Float64                  # terjedési sebesség
    t0::Float64                     # kiáradás kezdőideje (pl. 0.0)
end

# --- PulseIterator: mozgó forrásból generál gömbhullámokat ---
struct PulseIterator
    source::TimeSource
    dt::Float64                     # időlépés
    n_max::Int                      # iterációk száma
end

# # Gömbfelület generálása egyetlen hívással (GeometryBasics helper)
# function create_detailed_sphere(center::Point3f, radius::Float32, res::Int = 48)
#     sp     = Sphere(center, radius)               # beépített primitív
#     verts  = GeometryBasics.coordinates(sp, res)  # res×res pont
#     idxs   = GeometryBasics.faces(sp, res)        # indexlista
#     return GeometryBasics.Mesh(verts, idxs)
# end

# --- PulseIterator iterate metódus ---
Base.iterate(iter::PulseIterator, state = 0) =
    state > iter.n_max ? nothing : begin
        t        = iter.dt * state
        shift    = SVector(iter.source.speed * t, 0.0, 0.0)   # mozgás +X irányban
        position = iter.source.position0 + shift              # aktuális pozíció
        radius   = iter.source.speed * (iter.n_max * iter.dt - t)  # hátralévő idő × speed
        ((position, radius), state + 1)
    end

# --- Kezdő TimeSource példány ---
source_origin = TimeSource(SVector(0.0, 0.0, 0.0), 0.5, 0.0)

# PulseIterator beállítása (dt, lépésszám)
pulse_iter = PulseIterator(source_origin, 0.05, 100)

# --- Megjelenítés (scene) ---
include("3dtools.jl")
fig, scene = setup_scene(; use_axis3 = true)

# --- Gömbhéjak kirajzolása ---
for (pos, r) in pulse_iter
    meshscatter!(
        scene,                       # 3D tengely / jelenet
        [Point3f(pos...)],           # aktuális forráspont
        marker       = create_detailed_sphere(Point3f(0, 0, 0), 1f0, 48),  # előre generált gömb‑mesh
        markersize   = Float32(r),   # sugár → skálázás
        color        = RGBf(0.6, 1.0, 1.0),  # ciános árnyalat
        transparency = true,         # átlátszóság bekapcsolva
        alpha        = 0.05,         # áttetszőség mértéke
        shading      = NoShading,    # árnyékolás kikapcsolva (egyszínű héj)
    )
end

# --- Vízvonal kirajzolása (forrás pályája) ---
dt        = 0.05
steps     = 100
positions = [
    Point3f(                           # múltbeli pozíció pontlistában
        source_origin.position0[1] - source_origin.speed * dt * i,
        0.0,
        0.0,
    ) for i in 0:steps]
lines!(scene, positions; color = :white, linewidth = 1.5)

# A figure (jelenet) kirajzolása
fig
