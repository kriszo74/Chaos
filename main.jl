# ---- main.jl ----
using GLMakie
using StaticArrays
using GeometryBasics
using Observables      # Observable támogatás

# --- Globális paraméterek ---
E = 0.1       # hullámterjedési sebesség (fénysebesség) = időlépés
density = 1.0  # hullám density - időfelbontás
max_t = 10.0   # maximális szimuláció idő
t = Observable(0.0)  # globális idő

# --- Source (Hullámforrás) definíció ---
struct Source
    act_p::SVector{3, Float64}  # aktuális pozíció
    RV::SVector{3, Float64}     # mozgási sebesség vektor (RV=0 → álló forrás)
    bas_t::Float64              # indulási (bázis) idő
end

# TODO: GPU shader optimalizáció - t uniform átadása GPU-nak,
# sugár számítás shader-ben: radius = E * (t - birth_time)
# Így elkerülhető a buffer update minden frame-ben

# TODO: Observable alapú megjelenítés optimalizáció
# positions_obs = Observable(Point3f[])
# radii_obs = Observable(Float32[])
# meshscatter!(scene, positions_obs, markersize=radii_obs, ...)
# Így elkerülhető az új GPU buffer minden frame-ben

# --- Források frissítése ---
function update_sources!(sources::Vector{Source})
    positions = Point3f[]
    radii = Float32[]
    
    for i in 1:length(sources)
        source = sources[i]
        # Új pozíció kiszámítása: egy lépés előre RV * density irányban
        new_pos = source.act_p + source.RV * density
        
        # Pulse‑ok generálása 0‑tól t[]‑ig
        pulse_time = source.bas_t
        while pulse_time <= t[]
            # Pulse aktuális sugara
            radius = E * (t[] - pulse_time)
            
            push!(positions, Point3f(new_pos...))
            push!(radii, Float32(radius))
            
            pulse_time += density
        end
        
        # Forrás frissítése új pozícióval (bas_t változatlan)
        sources[i] = Source(new_pos, source.RV, source.bas_t)
    end
    
    return positions, radii
end

# --- Forráskonténer ---
sources = Vector{Source}()  # összes hullámforrás tárolója

# Teszt forrás létrehozása
push!(sources, Source(
    SVector(0.0, 0.0, 0.0),  # act_p: origó
    SVector(0.0, 0.0, 0.0),  # RV: álló forrás
    0.0                      # bas_t: 0 időpontban indul
))

# --- Megjelenítés (scene) ---
include("3dtools.jl")
fig, scene = setup_scene(; use_axis3 = true)

# A figure (jelenet) kirajzolása
display(fig)

# --- Időléptető async metódus ---
#@async 
begin
    while t[] < max_t
        # Források frissítése és pulse-ok generálása
        positions, radii = update_sources!(sources)
        
        # Megjelenítés (egyszerű verzió)
        if !isempty(positions)
            meshscatter!(scene, positions,
                markersize = radii,
                color = :cyan,
                transparency = true,
                alpha = 0.1)
        end
        
        t[] += E  # időlépés = E
        sleep(E)
    end
end
