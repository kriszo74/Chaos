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

# Pool‑infrastruktúra: fix méretű Observable‑tömbök aktív pulzusokhoz
const MAX_PULSES = 100_000  # konzervatív teszthatár – később állítható

# Minden pulzus pozíciója (Point3f) – induláskor (0,0,0)
positions_pool = Observable(fill(Point3f(0, 0, 0), MAX_PULSES))

# Minden pulzus sugara (Float32) – 0 = inaktív
radii_pool = Observable(fill(Float32(0), MAX_PULSES))

# -----------------------------------------------------------------------------
# ÚJ: Több forráshoz saját Observable‑párok tárolása
# Egyelőre a régi positions_pool / radii_pool a [1] elemként kerül ide,
# hogy a további kód változatlanul működjön.
# -----------------------------------------------------------------------------
const positions_pools = Vector{Observable{Vector{Point3f}}}()
const radii_pools     = Vector{Observable{Vector{Float32}}}()

push!(positions_pools, positions_pool)  # index 1 – legacy default
push!(radii_pools,    radii_pool)       # index 1 – legacy default

# -----------------------------------------------------------------------------
# Aktiváló függvény: új pulzus írása a legelső szabad slotba
# (egyelőre csak a "legacy" 1-es poolra mutat)
# -----------------------------------------------------------------------------
function activate_pulse!(pos::Point3f)
    # helyi másolatok a könnyebb íráshoz
    pos_vec   = positions_pool[]
    radii_vec = radii_pool[]
    idx = findfirst(==(0f0), radii_vec)   # 0 sugár = szabad slot
    if isnothing(idx)
        @warn "Pulse pool full!"
        return
    end
    pos_vec[idx]   = pos
    radii_vec[idx] = 0f0
    # visszaírjuk – ezzel pingeljük az Observable‑t
    positions_pool[] = pos_vec
    radii_pool[]     = radii_vec
end

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

# Egyetlen scatter a pool‑Observable‑ökkel
pool_scatter = meshscatter!(scene, positions_pool;
    markersize = radii_pool,
    color = :cyan,
    transparency = true,
    alpha = 0.1)

# A figure (jelenet) kirajzolása
display(fig)

# Async időléptető: forrásléptetés, pulzus‑aktiválás, sugártágítás
@async begin
    while t[] < max_t
        # 1) Források léptetése és új pulzus aktiválása
        for i in eachindex(sources)
            src = sources[i]
            new_pos = src.act_p + src.RV * density
            activate_pulse!(Point3f(new_pos...))
            sources[i] = Source(new_pos, src.RV, src.bas_t)
        end

        # 2) Sugár tágítása in-place
        radii_pool[] .+= Float32(E)
        # ping Observable, hogy a scatter frissüljön
        radii_pool[] = radii_pool[]

        # 3) időlépés és alvás
        t[] += E
        sleep(E)
    end
end

# -----------------------------------------------------------------------------
# ÚJ MÓDSZER (elszigetelt): pool-indexelt aktiválás
# -----------------------------------------------------------------------------
function activate_pulse!(pool_idx::Int, pos::Point3f)
    pos_obs = positions_pools[pool_idx]
    rad_obs = radii_pools[pool_idx]
    pos_vec = pos_obs[]
    rad_vec = rad_obs[]
    idx = findfirst(==(0f0), rad_vec)   # 0 sugár = szabad slot
    if isnothing(idx)
        @warn "Pulse pool $(pool_idx) full!"
        return
    end
    pos_vec[idx] = pos
    rad_vec[idx] = 0f0
    pos_obs[] = pos_vec
    rad_obs[]  = rad_vec
end

# Elszigetelt tesztpélda (nem fut automatikusan):
# Meghívás a REPL-ből:
#     demo_activate_pulse_pool1!()
# Elvárt: positions_pools[1][] első 0-sugarú slotja a megadott pozícióra áll.
function demo_activate_pulse_pool1!()
    activate_pulse!(1, Point3f(0, 0, 0))   # egyszerű próba a legacy poolon
    return (positions_pools[1][], radii_pools[1][])
end

