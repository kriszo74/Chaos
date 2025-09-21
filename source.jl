# ---- source.jl ----

# Forrás típus és műveletek – GUI‑független logika

# Source: mozgás és megjelenítési adatok
mutable struct Source
    act_p::SVector{3, Float64}   # aktuális pozíció
    RV::SVector{3, Float64}      # sebesség vektor
    RR::Float64                  # saját tengely körüli szögszerű paraméter (skalár, fénysebességhez viszonyítható)
    bas_t::Float64               # indulási idő
    positions::Vector{Point3d}   # pozíciók (Point3d)
    radii::Observable{Vector{Float64}}  # sugarak puffer
    color::Symbol                # szín
    alpha::Float64               # áttetszőség
    plot::Any                    # plot handle
end

# add_source!: forrás hozzáadása és vizuális regisztráció
# NOTE: a 'world' típusát szándékosan nem annotáljuk itt, hogy elkerüljük a körkörös
# függést (World a main.jl-ben van definiálva). Fail-fast hibák híváskor látszanak.
function add_source!(world, scene, src::Source)
    N = Int(ceil((world.max_t - src.bas_t) * world.density))  # pozíciók/sugarak előkészítése
    p_base = src.act_p + src.RV * src.bas_t                   # első impulzus pozíciója
    dp     = src.RV / world.density                           # két impulzus közti eltolás
    src.positions = [Point3d((p_base + dp * k)...) for k in 0:N-1]
    src.radii[] = fill(0.0, N)
    push!(world.sources, src)
    ph = meshscatter!(scene, src.positions;
        marker = create_detailed_sphere(Point3f(0, 0, 0), 1f0),
        markersize = src.radii,
        color = src.color,
        transparency = true,
        alpha = src.alpha)
    src.plot = ph
    return src
end

# Sugárvektor frissítése adott t-nél; meglévő pufferbe ír, aktív [1:K], a többi 0.
function update_radii(radii::Vector{Float64}, bas_t::Float64, tnow::Float64, density::Float64)
    dt_rel = (tnow - bas_t)
    K = ceil(Int, dt_rel * density)
    @inbounds begin
        for i in 1:K
            radii[i] = dt_rel - (i-1)/density
        end
        N = length(radii)
        if K < N
            fill!(view(radii, K+1:N), 0.0)
        end
    end
    return radii
end


# d,θ → p2 a Π₀ síkban (RV1-re merőleges sík, p1-en át)
# WHY: GUI‑független analitikus pozicionálás
function p2_from_dθ(p1::SVector{3,Float64}, RV1::SVector{3,Float64}, d::Float64, θ_deg::Float64)
    @assert d >= 0 "d must be >= 0"
    u = RV1 / sqrt(sum(abs2, RV1))                 # RV1 egységvektor
    refz = SVector(0.0, 0.0, 1.0); refy = SVector(0.0, 1.0, 0.0)
    ref  = abs(sum(refz .* u)) > 0.97 ? refy : refz  # WHY: fallback ha ~párhuzamos
    e2p  = ref - (sum(ref .* u)) * u                # vetítés Π₀ síkra
    e2   = e2p / sqrt(sum(abs2, e2p))               # síkbeli 0° irány
    e3   = SVector(u[2]*e2[3]-u[3]*e2[2],           # síkbeli ortho (u × e2)
                   u[3]*e2[1]-u[1]*e2[3],
                   u[1]*e2[2]-u[2]*e2[1])
    θ    = θ_deg * (pi/180)
    return p1 + d * (cos(θ) * e2 + sin(θ) * e3)
end


# -----------------------------------------------------------------------------
# calculate_coordinates: világállapotból (world) olvassa ki a referencia-forrást
# Viselkedés:
#   - ref === nothing  → pos=(0,0,0), RV_vec=(RV,0,0)
#   - különben world.sources[ref] alapján yaw/pitch szerint számol
# Megjegyzés: a függvény szándékosan nem annotál world típust, hogy elkerüljük a
# körkörös függést (World a main.jl-ben van definiálva).
# -----------------------------------------------------------------------------
function calculate_coordinates(world,
                               ref::Union{Nothing,Int},
                               RV::Float64,
                               distance::Float64,
                               yaw_deg::Float64,
                               pitch_deg::Float64)
    if ref === nothing
        return SVector(0.0, 0.0, 0.0), SVector(RV, 0.0, 0.0)
    end
    @assert 1 ≤ ref ≤ length(world.sources) "ref out of range: $(ref)"

    ref_pos = world.sources[ref].act_p
    ref_RV  = world.sources[ref].RV

    # u: ref_RV irány egységvektor
    u = ref_RV / sqrt(sum(abs2, ref_RV))
    # stabil referencia a merőleges bázishoz
    refz = SVector(0.0, 0.0, 1.0); refy = SVector(0.0, 1.0, 0.0)
    refv = abs(sum(refz .* u)) > 0.97 ? refy : refz
    # síkbázis ref_RV-re merőlegesen
    e2p = refv - (sum(refv .* u)) * u
    e2  = e2p / sqrt(sum(abs2, e2p))
    e3  = SVector(u[2]*e2[3]-u[3]*e2[2], u[3]*e2[1]-u[1]*e2[3], u[1]*e2[2]-u[2]*e2[1]) # u × e2

    # fok → radián
    yaw   = yaw_deg   * (pi/180)
    pitch = pitch_deg * (pi/180)

    # irányvektor yaw/pitch szerint (pitch 0° = Π₀, +pitch az u felé)
    dir = cos(pitch)*cos(yaw)*e2 + cos(pitch)*sin(yaw)*e3 + sin(pitch)*u
    dir = dir / sqrt(sum(abs2, dir))

    pos    = ref_pos + distance * dir
    RV_vec = RV * dir
    return pos, RV_vec
end
