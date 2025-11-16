# Forrás entitás és alap műveletek: pozíció, RV/irány, megjelenítés.
# GUI‑független, KISS utilok és állapotkezelés (regen+plot, UV).
# Spherical pozicionálás (distance/yaw/pitch) és compute_dir alapú irányszámítás.
#TODO: a függvények szignatúrájának felülvizsgálása, legyen egy logikus sorrend.
#TODO: a függvények logikus sorrendjének meghatározása

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
function add_source!(world, gctx, spec; abscol::Int)
    src = Source(
        SVector(0.0, 0.0, 0.0),                 # aktuális pozíció
        SVector(spec.RV, 0.0, 0.0),             # kezdő RV vektor
        spec.RR,                                # saját tengely körüli RR
        0.0,                                    # indulási idő
        [Point3d(SVector(0.0, 0.0, 0.0)...)],   # pálya első pontja a horgonyból
        Observable(Float64[]),                  # sugarak puffer (observable)
        gctx.atlas,                             # textúra atlasz
        0.2,                                    # alap áttetszőség
        nothing)                                # plot handle kezdetben üres
    
    if spec.ref !== nothing
        ref_src = world.sources[spec.ref]
        compute_spherical_position!(spec.distance, src, world, ref_src, spec.yaw_deg, spec.pitch_deg) #TODO: spec-et átadni egészben.
        compute_RV_direction!(spec.rv_yaw_deg, spec.rv_pitch_deg, src, world, ref_src) #TODO: spec-et átadni egészben.
    end
    N = Int(ceil((world.max_t - src.bas_t) * world.density)) # pozíciók/sugarak előkészítése
    src.radii[] = fill(0.0, N)                               # sugarpuffer előkészítése N impulzushoz
    src.positions = update_positions(N, src, world)          # kezdeti pozíciósor generálása aktuális RV-vel

    # UV-s marker és RR textúra alkalmazása
    src.plot = meshscatter!(
        gctx.scene,                             # 3D jelenet (LScene)
        src.positions;                          # forrás pályapontjai
        marker       = gctx.marker,             # UV-s gömb marker
        markersize   = src.radii,               # példányonkénti sugárvektor
        color        = src.color,               # textúra (Matrix{RGBAf})
        uv_transform = calculate_source_uv(abscol, gctx), # UV‑atlasz oszlop kiválasztása 
        rotation     = Vec3f(0.0, pi/4, 0.0),   # ideiglenes alapforgatás TODO: mesh módosítása, hogy ne kelljen alaprotáció.
        transparency = true,                    # átlátszóság engedélyezve
        alpha        = src.alpha,               # átlátszóság mértéke
        interpolate  = true,                    # textúrainterpoláció bekapcsolva
        shading      = true)                    # fény-árnyék aktív
    push!(world.sources, src)
    return src
end

# Sugárvektor frissítése adott t-nél; meglévő pufferbe ír, aktív [1:K], a többi 0.
# TODO: CUDA.jl: CuArray + egykernelű frissítés nagy N esetén
function update_radii(radii::Vector{Float64}, bas_t::Float64, t::Float64, density::Float64)
    dt_rel = (t - bas_t)                        # relatív idő az indulástól
    K = ceil(Int, dt_rel * density)             # aktív sugarak száma
    @inbounds begin
        for i in 1:K                            # aktív szegmensek frissítése
            radii[i] = dt_rel - (i-1)/density   # sugár idő az i. impulzushoz
        end
        N = length(radii)                       # pufferhossz
    K < N && fill!(view(radii, K+1:N), 0.0)     # inaktív szakasz nullázása
    end
    return radii                                # frissített puffer
end

# Pozíciók újragenerálása adott N alapján
# TODO: CUDA.jl: pályapontok generálása GPU-n; visszamásolás minimalizálása
function update_positions(N::Int, src::Source, world)
    dp = src.RV / world.density            # két impulzus közti eltolás TODO: ezt a hányadost RV változásakor kellene számolni!
    return [Point3d((src.positions[1] + dp * k)...) for k in 0:N-1]  # pálya N ponttal
end

# Sugarak frissítése a world.t alapján
# TODO: CUDA.jl: radii batch futtatása GPU-n (több forrás, szegmensek)
function apply_time!(world)
    @inbounds for src in world.sources # források bejárása
        src.radii[] = update_radii(src.radii[], src.bas_t, world.t[], world.density)  # sugarpuffer frissítése
    end
end

# RV skálázása; irány megtartása
function rescale_RV_vec(RV::Float64, src::Source, world)
    u = src.RV / sqrt(sum(abs2, src.RV))    # irány megtartása: normalizálás és skálázás
    src.RV = u * RV                         # skálázott RV beállítása
    apply_pose!(src, world)                 # pálya újragenerálása és plot frissítése
end

# Referencia irány (yaw/pitch) alapján horgony beállítása
function compute_spherical_position!(distance::Float64, src::Source, world, ref_src::Source, yaw_deg::Float64, pitch_deg::Float64)
    ref_pos = SVector(ref_src.positions[1]...)      # referencia horgony pozíciója (SVector)
    dir = compute_dir(ref_src, yaw_deg, pitch_deg)  # ref RV-hez mért irány (yaw/pitch)
    src.act_p = ref_pos + distance * dir            # új horgony pozíció távolság és irány szerint
    src.positions[1] = Point3d(src.act_p...)        # pálya első pontja a horgonyból
end

# RV irány beállítása; pozíció nem változik
function compute_RV_direction!(yaw_deg::Float64, pitch_deg::Float64, src::Source, world, ref_src::Source)
    rv_mag = sqrt(sum(abs2, src.RV))                # RV nagyságának megtartása
    dir = compute_dir(ref_src, yaw_deg, pitch_deg)  # új irány számítása yaw/pitch alapján
    src.RV = rv_mag * dir                           # irány frissítése; horgony változatlan
end

function update_RV_direction!(yaw_deg::Float64, pitch_deg::Float64, src::Source, world, ref_src::Source)
    compute_RV_direction!(yaw_deg, pitch_deg, src, world, ref_src)
    apply_pose!(src, world)
end

function update_spherical_position!(distance::Float64, src::Source, world, ref_src::Source, yaw_deg::Float64, pitch_deg::Float64)
    compute_spherical_position!(distance, src, world, ref_src, yaw_deg, pitch_deg)
    apply_pose!(src, world)
end

# Pozíció alkalmazása: pálya és plot frissítése
function apply_pose!(src::Source, world)
    src.positions = update_positions(length(src.positions), src, world)  # pálya újragenerálása
    src.plot[:positions][] = src.positions                               # plot frissítése
end

# Irányvektor a ref RV tengelyéhez mérve (yaw/pitch)
function compute_dir(ref_src::Source, yaw_deg::Float64, pitch_deg::Float64)
    ref_RV = ref_src.RV                        # referencia RV vektora
    u = ref_RV / sqrt(sum(abs2, ref_RV))       # ref RV irányegység
    refz = SVector(0.0, 0.0, 1.0); refy = SVector(0.0, 1.0, 0.0)    # stabil referencia vektorok
    refv = abs(sum(refz .* u)) > 0.97 ? refy : refz                 # fallback, ha közel párhuzamos
    e2p = refv - (sum(refv .* u)) * u          # u-ra merőleges komponens
    e2  = e2p / sqrt(sum(abs2, e2p))           # normalizált e2
    e3  = SVector(u[2]*e2[3]-u[3]*e2[2], u[3]*e2[1]-u[1]*e2[3], u[1]*e2[2]-u[2]*e2[1])  # e3 = u × e2
    yaw   = yaw_deg   * (pi/180)               # fok → radián
    pitch = pitch_deg * (pi/180)               # fok → radián
    dir = cos(pitch)*cos(yaw)*e2 + cos(pitch)*sin(yaw)*e3 + sin(pitch)*u  # irány komponensek
    return dir / sqrt(sum(abs2, dir))          # egységvektor visszaadása
end

# UV oszlop indexből uv_transform kiszámítása
function calculate_source_uv(abscol::Int, gctx)
    @dbg_assert(1 <= abscol <= gctx.cols, "abscol out of range")    # érvényes atlasz oszlop
    u0 = Float32((abscol - 1) / gctx.cols)                          # oszlop kezdő U koordináta
    sx = 1f0 / Float32(gctx.cols)                                   # oszlopszélesség
    return Makie.uv_transform((Vec2f(0f0, u0 + sx/2), Vec2f(1f0, 0f0))) # UV eltolás + skálázás
end

# UV‑transzform frissítése a forráson
function update_source_uv!(abscol::Int, src::Source, gctx)
    src.plot[:uv_transform][] = calculate_source_uv(abscol, gctx)   # UV transzform beállítása
end

# RR skálár frissítése és 1×3 textúra beállítása (piros–szürke–kék)
function update_source_RR(new_RR::Float64, src::Source, gctx, abscol::Int)
    src.RR = new_RR                         # RR skálár frissítése
    update_source_uv!(abscol, src, gctx)    # textúra oszlop frissítése
    return src
end
