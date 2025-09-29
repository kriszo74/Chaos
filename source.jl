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
    N = Int(ceil((world.max_t - src.bas_t) * world.density)) # pozíciók/sugarak előkészítése
    src.radii[] = fill(0.0, N)                               # sugarpuffer előkészítése N impulzushoz
    src.positions = [Point3d(src.act_p...)]                    # horgony: első pont a kiinduló pozíció
    src.positions = update_positions(N, src, world)            # kezdeti pozíciósor generálása aktuális RV-vel
    push!(world.sources, src)
    # Instancing: rr_spheres! wrapper (egyelőre egyszínű, később shaderes Doppler)
    rv = src.RV; len = sqrt(sum(abs2, rv))
    omega_dir = len > 0 ? Makie.Vec3f(Float32(rv[1]/len), Float32(rv[2]/len), Float32(rv[3]/len)) : Makie.Vec3f(1,0,0)
    ph = rr_spheres!(scene;
        positions   = src.positions,
        radii       = src.radii,
        base_color  = src.color,
        alpha       = src.alpha,
        rr          = RRParams(omega_dir=omega_dir, RR_scalar=Float32(src.RR)))
    src.plot = ph
    return src
end

# Sugárvektor frissítése adott t-nél; meglévő pufferbe ír, aktív [1:K], a többi 0.
function update_radii(radii::Vector{Float64}, bas_t::Float64, t::Float64, density::Float64)
    dt_rel = (t - bas_t)
    K = ceil(Int, dt_rel * density)
    @inbounds begin
        for i in 1:K
            radii[i] = dt_rel - (i-1)/density
        end
        N = length(radii)
    K < N && fill!(view(radii, K+1:N), 0.0)
    end
    return radii
end

# Pozíciók újragenerálása adott N alapján
function update_positions(N::Int, src::Source, world)
    dp = src.RV / world.density            # két impulzus közti eltolás
    return [Point3d((src.positions[1] + dp * k)...) for k in 0:N-1]
end

# Idő szerinti vizuális állapot alkalmazása (scrub/play)
# Csak a sugarakat frissíti a world.t alapján. Később bővíthető a pozíciókra is.
function apply_time!(world)
    @inbounds for src in world.sources
        src.radii[] = update_radii(src.radii[], src.bas_t, world.t[], world.density)
    end
end

# RV skálár frissítése + positions újragenerálása (irány megtartása)
# Paraméterek: RV (nagyság), src (forrás), world (világállapot)
function update_source_RV(RV::Float64, src::Source, world)
    # irány megtartása: pitch=90°, distance=0, yaw=0 → dir == u
    _, src.RV = calculate_coordinates(world, src, RV, 0.0, 0.0, 90.0)
    src.plot[:positions][] = src.positions = update_positions(length(src.positions), src, world)
end

# Koordináták számítása referenciaként adott src alapján
# - src == nothing → pos=(0,0,0), RV_vec=(RV,0,0)
# - különben a src aktuális akt_p/RV értékeihez képest yaw/pitch szerint számol
function calculate_coordinates(world,
                               src::Union{Nothing,Source},
                               RV::Float64,
                               distance::Float64,
                               yaw_deg::Float64,
                               pitch_deg::Float64)
    isnothing(src) && return SVector(0.0, 0.0, 0.0), SVector(RV, 0.0, 0.0)
    ref_pos = src.act_p
    ref_RV  = src.RV

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

