# Forrás entitás és alap műveletek: pozíció, RV/irány, megjelenítés.
# GUI‑független, KISS utilok és állapotkezelés (regen+plot, UV).
# Spherical pozicionálás (distance/yaw/pitch) és compute_dir alapú irányszámítás.
#TODO: a függvények szignatúrájának felülvizsgálása, legyen egy logikus sorrend.

# Source: mozgás és megjelenítési adatok
mutable struct Source
    act_p::SVector{3, Float64}   # aktuális pozíció
    RV::SVector{3, Float64}      # sebesség vektor TODO: RV-t külön tároljuk egységvektorként, amelyből származtatjuk a tényleges vektort.
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
        update_spherical_position!(spec.distance, src, world, ref_src, spec.yaw_deg, spec.pitch_deg) #TODO: spec-et átadni egészben.
        update_RV_direction!(spec.rv_yaw_deg, spec.rv_pitch_deg, src, world, ref_src) #TODO: spec-et átadni egészben.
    end
    N = Int(ceil((world.max_t - src.bas_t) * world.density)) # pozíciók/sugarak előkészítése
    src.radii[] = fill(0.0, N)                               # sugarpuffer előkészítése N impulzushoz
    src.positions = compute_positions(N, src, world)         # kezdeti pozíciósor generálása aktuális RV-vel

    # UV-s marker és RR textúra alkalmazása
    src.plot = meshscatter!(
        gctx.scene,                             # 3D jelenet (LScene)
        src.positions;                          # forrás pályapontjai
        marker       = gctx.marker,             # UV-s gömb marker
        markersize   = src.radii,               # példányonkénti sugárvektor
        color        = src.color,               # textúra (Matrix{RGBAf})
        uv_transform = compute_source_uv(abscol, gctx), # UV‑atlasz oszlop kiválasztása 
        rotation     = Vec3f(0.0, pi/4, 0.0),   # ideiglenes alapforgatás TODO: mesh módosítása, hogy ne kelljen alaprotáció.
        transparency = true,                    # átlátszóság engedélyezve
        alpha        = src.alpha,               # átlátszóság mértéke
        interpolate  = true,                    # textúrainterpoláció bekapcsolva
        shading      = true)                    # fény-árnyék aktív
    push!(world.sources, src)
    return src
end

# Sugarak frissítése a world.t alapján
# TODO: CUDA.jl: radii batch futtatása GPU-n (több forrás, szegmensek)
function apply_world_time!(world)
    @inbounds for src in world.sources # források bejárása
        src.radii[] = update_radii!(src, world)  # sugarpuffer frissítése
    end
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
    yaw   = yaw_deg   * (pi/180)               # fok → radián TODO: fok radián konverzió megszüntetése
    pitch = pitch_deg * (pi/180)               # fok → radián TODO: fok radián konverzió megszüntetése
    dir = cos(pitch)*cos(yaw)*e2 + cos(pitch)*sin(yaw)*e3 + sin(pitch)*u  # irány komponensek TODO: sincos
    return dir / sqrt(sum(abs2, dir))          # egységvektor visszaadása
end

# Pozíciók újragenerálása adott N alapján
# TODO: CUDA.jl: pályapontok generálása GPU-n; visszamásolás minimalizálása
function compute_positions(N::Int, src::Source, world)
    dp = src.RV / world.density            # két impulzus közti eltolás TODO: ezt a hányadost RV változásakor kellene számolni!
    return [Point3d((src.positions[1] + dp * k)...) for k in 0:N-1]  # pálya N ponttal
end

# UV oszlop indexből uv_transform kiszámítása
function compute_source_uv(abscol::Int, gctx)
    u0 = Float32((abscol - 1) / gctx.cols)                          # oszlop kezdő U koordináta
    sx = 1f0 / Float32(gctx.cols)                                   # oszlopszélesség
    return Makie.uv_transform((Vec2f(0f0, u0 + sx/2), Vec2f(1f0, 0f0))) # UV eltolás + skálázás
end

# Sugárvektor frissítése adott t-nél; meglévő pufferbe ír, aktív [1:K], a többi 0.
# TODO: CUDA.jl: CuArray + egykernelű frissítés nagy N esetén
function update_radii!(src::Source, world)
    radii = src.radii[]                         # sugárpuffer
    dt_rel = (world.t[] - src.bas_t)            # relatív idő az indulástól
    K = ceil(Int, dt_rel * world.density)       # aktív sugarak száma
    @inbounds begin
        for i in 1:K                            # aktív szegmensek frissítése
            radii[i] = r = dt_rel - (i-1) / world.density   # sugár idő az i. impulzushoz
            #apply_wave_hit!(src, world, i, r)
        end
        N = length(radii)                       # pufferhossz
        K < N && fill!(view(radii, K+1:N), 0.0) # inaktív szakasz nullázása # TODO: csak első futásnál és visszatkerésnél szükséges. Amúgy érdemes átlépni.
    end
    return radii                                # frissített puffer
end

# Hullámtéri találat: kifelé igazítja a cél RV-jét
function apply_wave_hit!(src::Source, world)
    radii = src.radii[]
    for tgt in world.sources                        # ütközésvizsgálat minden forrásra (self is)
        k = 0; gap = typemax(Float64); r2 = 0.0
        @inbounds for act_k in eachindex(radii)
            ract_k = radii[act_k]
            ract_k == 0 && break
            
            # r^2 és célpont távolság^2 különbség számítása
            r2act_k = ract_k * ract_k       # a vizsgált impulzus sugárának négyzete
            d2k = sum(abs2, SVector(src.positions[act_k]...) - tgt.act_p)
            act_gap = r2act_k - d2k
            
            # pozitív, legkisebb rádiusz-gap választása
            if act_gap < 0 || act_gap >= gap; continue; end
            gap = act_gap
            k = act_k
            r2 = r2act_k   # a legközelebbi impulzus sugárának négyzete
        end
        @info "k = $(k)"
        k == 0 && continue
        p  = SVector(src.positions[k]...)           # legközelebbi impulzus középpontja

        to_tgt = tgt.act_p - p                      # irányvektor: p -> tgt.akt_p
        to_tgt2  = sum(abs2, to_tgt)                # to_tgt irányvektor hosszának a négyzete gyors összehasonlításhoz
        @info "to_tgt2 = $(to_tgt2), r2 = $(r2))"
        to_tgt2 <= r2 || continue                   # csak akkor megyünk tovább, ha to_tgt2 ≤ r2 (gömbön belül)

        # ütközés történt, to_tgt egységvektorának meghatározása
        to_tgt_mag = sqrt(to_tgt2)                  # to_tgt irányvektor hossza
        to_tgt_mag == 0 && continue
        to_tgt_u = to_tgt / to_tgt_mag              # to_tgt egységvektora TODO: input oldalon tiltani a 0 távolságot és ütköző yaw/pitch kombinációkat

        # kiszámítjuk aktuális impulzushoz (p) tartozó forrás (src) RV-jének egységvektorát.
        src_rv_dir = k < length(src.positions) ? SVector(src.positions[k+1]...) - p : src.RV / world.density # src.RV irányvektora TODO: legyen csak simán SVector(src.positions[i+1]...) - p, inkább + 1 pozíciót generálni.
        src_rv_dir_mag = sqrt(sum(abs2, src_rv_dir))# src.RV irányvektor hossza
        src_rv_dir_mag == 0 && continue
        src_rv_u = src_rv_dir / src_rv_dir_mag      # src.RV egységvektora TODO: RV = 0-t tiltani, helyette RV = 0.0000001 (vagy még kisebb), ami az ábrázoláson nem látszik.

        # múlttérsűrűség és taszítási vektor számítás
        cosθ = sum(to_tgt_u .* src_rv_u)            # két egységvektor (to_tgt_u, t_axis_u) skaláris szorzata = cosθ: vektor elemeit összeszorozzuk és szummázzuk.
        src_rv_mag = src_rv_dir_mag * world.density # src.RV nagyság közelítése a diszkrét lépésből
        src_impulse_gap = world.E - cosθ * src_rv_mag# két impulzus távolsága TODO: E csak is 1 lehet, E skálázása helyett inkább anim sebességet kellene bevezetni!
        src_impulse_gap == 0 && continue            # végetelen múlttérsűrűség. TODO: a forrás mintha egy labda falnak ütközne. Igazából ennek is van egy matematikája, a density-t a végtelenhez közelítjük.
        ρ = 1 / abs(src_impulse_gap)                # múlttérsűrűség
        src_v = to_tgt_u * ρ                        # taszítási vektor

        # forgató eltolás
        rot_dir = cross(src_rv_u, to_tgt_u)         # forgástengellyel és találattal derékszögben
        rot_mag = sqrt(sum(abs2, rot_dir))          # forgás irány hossz
        rot = rot_mag == 0 ? rot_dir : rot_dir / rot_mag * src.RR

        # eredő vektor számítás és tgt.RV irányba állítása
        tgt_step = (tgt.RV + src_v + rot) / world.density # ez az eredő vektor, ezt kell hozzáadni tgt.positions[k]-hoz
        tgt_rv_mag = sqrt(sum(abs2, tgt.RV))        # aktuális tgt.RV hossza
        tgt_rv_mag == 0 && continue                 # nulla RV: nincs frissítés
        tgt_step_mag = sqrt(sum(abs2, tgt_step))    # step hossza
        tgt_step_mag == 0 && continue               # nulla step: nincs irány
        tgt.RV = tgt_step / tgt_step_mag * tgt_rv_mag# új irány: step irányába, eredeti nagysággal
        
        #TODO: a pálya frissítését compute_positions/apply_pose! kezelje!
        if k < length(tgt.positions)           # csak ha van következő pont 
            tgt.positions[k+1] = Point3d((tgt.positions[k] + tgt_step)...) # következő pont frissítése
            tgt.plot[:positions][] = tgt.positions  # plot pozíciók frissítése
            #@infiltrate
        end
    end
end

# Referencia irány (yaw/pitch) alapján horgony beállítása
function update_spherical_position!(distance::Float64, src::Source, world, ref_src::Source, yaw_deg::Float64, pitch_deg::Float64)
    ref_pos = SVector(ref_src.positions[1]...)      # referencia horgony pozíciója (SVector)
    dir = compute_dir(ref_src, yaw_deg, pitch_deg)  # ref RV-hez mért irány (yaw/pitch)
    src.act_p = ref_pos + distance * dir            # új horgony pozíció távolság és irány szerint
    src.positions[1] = Point3d(src.act_p...)        # pálya első pontja a horgonyból
end

# RV irány beállítása; pozíció nem változik
function update_RV_direction!(yaw_deg::Float64, pitch_deg::Float64, src::Source, world, ref_src::Source)
    rv_mag = sqrt(sum(abs2, src.RV))                # RV nagyságának megtartása
    dir = compute_dir(ref_src, yaw_deg, pitch_deg)  # új irány számítása yaw/pitch alapján
    src.RV = rv_mag * dir                           # irány frissítése; horgony változatlan
end

# Pozíció alkalmazása: pálya és plot frissítése
function apply_pose!(src::Source, world)
    src.positions = compute_positions(length(src.positions), src, world)  # pálya újragenerálása
    src.plot[:positions][] = src.positions                                # plot frissítése
end

# RV skálázása; irány megtartása
function apply_RV_rescale!(RV::Float64, src::Source, world)
    u = src.RV / sqrt(sum(abs2, src.RV))    # irány megtartása: normalizálás és skálázás
    src.RV = u * RV                         # skálázott RV beállítása
    apply_pose!(src, world)                 # pálya újragenerálása és plot frissítése
end

function apply_RV_direction!(yaw_deg::Float64, pitch_deg::Float64, src::Source, world, ref_src::Source)
    update_RV_direction!(yaw_deg, pitch_deg, src, world, ref_src)
    apply_pose!(src, world)
end

function apply_spherical_position!(distance::Float64, src::Source, world, ref_src::Source, yaw_deg::Float64, pitch_deg::Float64)
    update_spherical_position!(distance, src, world, ref_src, yaw_deg, pitch_deg)
    apply_pose!(src, world)
end

# UV‑transzform frissítése a forráson
function apply_source_uv!(abscol::Int, src::Source, gctx)
    src.plot[:uv_transform][] = compute_source_uv(abscol, gctx)   # UV transzform beállítása
end

# RR skálár frissítése és 1×3 textúra beállítása (piros–szürke–kék)
function apply_source_RR!(new_RR::Float64, src::Source, gctx, abscol::Int)
    src.RR = new_RR                         # RR skálár frissítése
    apply_source_uv!(abscol, src, gctx)     # textúra oszlop frissítése
    return src
end
