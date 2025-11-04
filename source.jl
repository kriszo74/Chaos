# Forrás típus és műveletek – GUI‑független logika

# Source: mozgás és megjelenítési adatok
mutable struct Source
    act_p::SVector{3, Float64}   # aktuális pozíció
    RV::SVector{3, Float64}      # sebesség vektor
    RR::Float64                  # saját tengely körüli szögszerű paraméter (skalár, fénysebességhez viszonyítható)
    bas_t::Float64               # indulási idő
    positions::Vector{Point3d}   # pozíciók (Point3d)
    radii::Observable{Vector{Float64}}  # sugarak puffer
    color::Matrix{RGBAf}         # textúra MxN színmátrix (pl. 3x1 RGBAf)
    alpha::Float64               # áttetszőség
    plot::Any                    # plot handle
end

# forrás hozzáadása és vizuális regisztráció (közvetlen meshscatter! UV-s markerrel és RR textúrával)
function add_source!(world, src::Source, gctx; abscol::Int)
    N = Int(ceil((world.max_t - src.bas_t) * world.density)) # pozíciók/sugarak előkészítése
    src.radii[] = fill(0.0, N)                               # sugarpuffer előkészítése N impulzushoz
    src.positions = [Point3d(src.act_p...)]                  # horgony: első pont a kiinduló pozíció
    src.positions = update_positions(N, src, world)          # kezdeti pozíciósor generálása aktuális RV-vel
    push!(world.sources, src)

    # UV-s marker és RR textúra alkalmazása
    src.plot = meshscatter!(gctx.scene, src.positions;
        marker       = gctx.marker,            # UV-s gömb marker
        markersize   = src.radii,              # példányonkénti sugárvektor
        color        = src.color,              # textúra (Matrix{RGBAf})
        uv_transform = calculate_source_uv(abscol, gctx), # UV‑atlasz oszlop kiválasztása 
        rotation     = Vec3f(0.0, pi/4, 0.0),  # ideiglenes alapforgatás TODO: mesh módosítása, hogy ne kelljen alaprotáció.
        transparency = true,                   # átlátszóság engedélyezve
        alpha        = src.alpha,              # átlátszóság mértéke
        interpolate  = true,                   # textúrainterpoláció bekapcsolva
        shading      = true)                   # fény-árnyék aktív
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
function rescale_RV_vec(RV::Float64, src::Source, world)
    # irány megtartása: aktuális RV normalizálása és skálázása
    u = src.RV / sqrt(sum(abs2, src.RV))
    src.RV = u * RV
    src.plot[:positions][] = src.positions = update_positions(length(src.positions), src, world)
end

# distance frissítése referencia alapján; RV nem változik
function update_distance(distance::Float64, src::Source, world, ref_src::Source, yaw_deg::Float64, pitch_deg::Float64)
    pos, _ = calculate_coordinates(world, ref_src, sqrt(sum(abs2, src.RV)), distance, yaw_deg, pitch_deg)
    apply_pose!(src, world, pos)
end

# yaw/pitch frissítése referencia alapján; RV iránya követi, nagysága marad
function update_yaw_pitch(yaw_deg::Float64, pitch_deg::Float64, src::Source, world, ref_src::Source, distance::Float64)
    rv_mag = sqrt(sum(abs2, src.RV))
    pos, RVv = calculate_coordinates(world, ref_src, rv_mag, distance, yaw_deg, pitch_deg)
    src.RV = RVv
    apply_pose!(src, world, pos)
end

# Pozíció alkalmazása: act_p, pálya és plot frissítése
function apply_pose!(src::Source, world, pos)
    src.act_p = pos
    src.positions[1] = Point3d(pos...)
    src.positions = update_positions(length(src.positions), src, world)
    src.plot[:positions][] = src.positions
end

# UV oszlop indexből uv_transform kiszámítása
function calculate_source_uv(abscol::Int, gctx)
    @dbg_assert(1 <= abscol <= gctx.cols, "abscol out of range")
    u0 = Float32((abscol - 1) / gctx.cols)
    sx = 1f0 / Float32(gctx.cols)
    return Makie.uv_transform((Vec2f(0f0, u0 + sx/2), Vec2f(1f0, 0f0)))
end

function update_source_uv!(abscol::Int, src::Source, gctx)
    src.plot[:uv_transform][] = calculate_source_uv(abscol, gctx)
end

# RR skálár frissítése és 1×3 textúra beállítása (piros–szürke–kék)
function update_source_RR(new_RR::Float64, src::Source, gctx, abscol::Int)
    src.RR = new_RR
    update_source_uv!(abscol, src, gctx)
    return src
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
    ref_pos = SVector(src.positions[1]...)
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

