# Forrás entitás és alap műveletek: pozíció, RV/irány, megjelenítés.
# GUI‑független, KISS utilok és állapotkezelés (regen+plot, UV).
# Spherical pozicionálás (distance/yaw/pitch) és compute_dir alapú irányszámítás.
#TODO: a függvények szignatúrájának felülvizsgálása, legyen egy logikus sorrend.

# Source: mozgás és megjelenítési adatok
mutable struct Source
    act_p::SVector{3, Float64}   # aktuális pozíció
    act_k::Int                   # aktuális index
    RV::SVector{3, Float64}      # sebesség vektor TODO: RV-t külön tároljuk egységvektorként, amelyből származtatjuk a tényleges vektort.
    base_RV::SVector{3, Float64} # alap RV vektor (seek resethez)
    RR::Float64                  # saját tengely körüli szögszerű paraméter (skalár, fénysebességhez viszonyítható)
    bas_t::Float64               # indulási idő
    positions::Vector{Point3d}   # pozíciók (Point3d)
    radii::Observable{Vector{Float64}}  # sugarak puffer
    plot::Any                    # plot handle
end

# forrás hozzáadása és vizuális regisztráció (közvetlen meshscatter! UV-s markerrel és RR textúrával)
function add_source!(world, gctx, spec; abscol::Int)
    src = Source(
        SVector(0.0, 0.0, 0.0),                 # aktuális pozíció
        0,                                      # aktuális index
        SVector(spec.RV, 0.0, 0.0),             # kezdő RV vektor
        SVector(spec.RV, 0.0, 0.0),             # alap RV vektor
        spec.RR,                                # saját tengely körüli RR
        0.0,                                    # indulási idő
        [Point3d(SVector(0.0, 0.0, 0.0)...)],   # pálya első pontja a horgonyból
        Observable(Float64[]),                  # sugarak puffer (observable)
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
        color        = gctx.atlas,              # textúra (Matrix{RGBAf})
        uv_transform = compute_source_uv(abscol, gctx), # UV‑atlasz oszlop kiválasztása 
        rotation     = Vec3f(0.0, pi/4, 0.0),   # ideiglenes alapforgatás TODO: mesh módosítása, hogy ne kelljen alaprotáció.
        transparency = true,                    # átlátszóság engedélyezve
        interpolate  = true,                    # textúrainterpoláció bekapcsolva
        shading      = true)                    # fény-árnyék aktív
    push!(world.sources, src)
    return src
end

# Sugarak frissítése a world.t alapján
# TODO: CUDA.jl: radii batch futtatása GPU-n (több forrás, szegmensek)
function step_world!(world; step = world.E / 60)
    update_radii!(world)  # sugárpuffer frissítése
    apply_wave_hit!(world)
    for src in world.sources
        p_ix = min(src.act_k + 1, length(src.positions))
        act_pos = src.act_p + src.RV * step
        src.positions[p_ix] = Point3d(act_pos...)
        src.plot[:positions][] = src.positions
        src.act_p = act_pos
    end
end

# Irányvektor a ref RV tengelyéhez mérve (yaw/pitch)
function compute_dir(ref_src::Source, yaw_deg::Float64, pitch_deg::Float64)
    ref_RV = ref_src.base_RV                   # referencia RV vektora
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
function update_radii!(world)
    @inbounds for src in world.sources # források bejárása
        radii = src.radii[]                         # sugárpuffer
        dt_rel = (world.t[] - src.bas_t)            # relatív idő az indulástól
        K = ceil(Int, dt_rel * world.density)       # aktív sugarak száma
        src.act_k = K                               # aktuális index
        @inbounds begin
            for i in 1:K                            # aktív szegmensek frissítése
                radii[i] = r = dt_rel - (i-1) / world.density   # sugár idő az i. impulzushoz
            end
            N = length(radii)                       # pufferhossz
            K < N && fill!(view(radii, K+1:N), 0.0) # inaktív szakasz nullázása # TODO: csak első futásnál és visszatekerésnél szükséges. Amúgy érdemes átlépni.
        end
        src.radii[] = radii             # sugárpuffer frissítése
    end
end

# Hullámtéri találat: kifelé igazítja a cél RV-jét
const eps_tol = 1e-9
function apply_wave_hit!(world)
    for emt in world.sources
        emt_radii = emt.radii[]                 # emmiter (emt) sugárpuffer pillanatképe
        for rcv in world.sources                # ütközésvizsgálat minden forrásra (self is)
            emt_k = 0; min_gap2 = typemax(Float64); r2_min_emt = to_rcv2 = 0.0; emt_p = to_rcv = SVector(0.0, 0.0, 0.0);
            @inbounds for erix in eachindex(emt_radii)  # erix: Emmitter (emt) Radius (radii) IndeX
                r_erix = emt_radii[erix]        # aktuális emitter impulzus sugara
                r_erix == 0 && break            # az első 0 után a maradék is inaktív, kilépünk a ciklusból
                
                # r^2 és célpont távolság^2 különbség számítása
                r2_erix = r_erix * r_erix               # a vizsgált emitter impulzus sugárának négyzete
                p_erix  = SVector(emt.positions[erix]...)   # a vizsgált emitter impulzus középpontja
                to_rcv_erix = rcv.act_p - p_erix        # irányvektor: p (a vizsgált emitter impulzus középpontja) -> rcv.akt_p
                to_rcv2_erix = sum(abs2, to_rcv_erix)   # a vizsgált emitter impulzus középpontja és receiver forrás távolság^2-e
                act_gap2 = r2_erix - to_rcv2_erix       # r^2 és távolság^2 különbsége
                
                # pozitív, legkisebb rádiusz-gap feljegyzése
                if act_gap2 < 0 || act_gap2 >= min_gap2; continue; end # nem ütközik vagy nem ez a legközelebbi
                min_gap2 = act_gap2             # új legkisebb rádiusz-gap, amely emitter impulzuson beül van.
                emt_k = erix                    # a legkisebb rádiusz-gap-hoz tartozó index (erix)
                r2_min_emt = r2_erix            # a legközelebbi impulzus sugárának négyzete
                emt_p = p_erix                  # a legközelebbi impulzus középpontja
                to_rcv = to_rcv_erix            # a legkisebb irányvektor: emt_p -> rcv.akt_p
                to_rcv2 = to_rcv2_erix          # a legközelebbi impulzus középpontja és receiver forrás távolság^2-e
            end
            if emt_k == 0 || to_rcv2 < eps_tol || r2_min_emt - to_rcv2 < eps_tol; continue; end
            # TODO: számold a relatív sebesség radiális komponensét, és ha kifelé megy (dot(to_rcv_u, rcv.RV) ≥ 0), akkor continue; így csak befelé haladva érvényesül az impulzus.

            # ütközés történt, to_tgt egységvektorának meghatározása
            to_rcv_u, _ = unit_and_mag(to_rcv); isnothing(to_rcv_u) && continue # to_tgt egységvektora TODO: input oldalon tiltani a 0 távolságot és ütköző yaw/pitch kombinációkat

            # kiszámítjuk aktuális impulzushoz (p) tartozó forrás (src) RV-jének egységvektorát.
            emt_rv_dir = emt_k < length(emt.positions) ? SVector(emt.positions[emt_k+1]...) - emt_p : emt.RV / world.density # src.RV irányvektora TODO: legyen csak simán SVector(src.positions[i+1]...) - p, inkább + 1 pozíciót generálni.
            emt_rv_u, emt_rv_dir_mag = unit_and_mag(emt_rv_dir); isnothing(emt_rv_u) && continue # src.RV egységvektora és hossza TODO: RV = 0-t tiltani, helyette RV = 0.0000001 (vagy még kisebb), ami az ábrázoláson nem látszik.

            # múlttérsűrűség és taszítási vektor számítás
            cosθ = sum(to_rcv_u .* emt_rv_u)           # két egységvektor (to_rcv_u, emt_rv_u) skaláris szorzata = cosθ: vektor elemeit összeszorozzuk és szummázzuk.
            emt_rv_mag = emt_rv_dir_mag * world.density# src.RV nagyság közelítése a diszkrét lépésből
            emt_impulse_gap = world.E - cosθ * emt_rv_mag# két impulzus távolsága TODO: E csak is 1 lehet, E skálázása helyett inkább anim sebességet kellene bevezetni!
            emt_impulse_gap == 0 && continue           # végetelen múlttérsűrűség. TODO: a forrás mintha egy labda falnak ütközne. Igazából ennek is van egy matematikája, a density-t a végtelenhez közelítjük.
            ρ = 1 / abs(emt_impulse_gap)               # múlttérsűrűség
            emt_v = to_rcv_u * ρ                       # taszítási vektor

            # forgató eltolás
            emt_rot_dir = cross(emt_rv_u, to_rcv_u)    # forgástengellyel és találattal derékszögben
            emt_rot_u, _ = unit_and_mag(emt_rot_dir)
            emt_rot = isnothing(emt_rot_u) ? emt_rot_dir : emt_rot_u * emt.RR

            # eredő vektor számítás és tgt.RV irányba állítása
            rcv_step = (rcv.RV + emt_v + emt_rot) / world.density # ez az eredő vektor, ezt kell hozzáadni rcv.positions[k]-hoz
            rcv_rv_mag = sqrt(sum(abs2, rcv.RV))        # aktuális rcv.RV hossza
            rcv_rv_mag == 0 && continue                 # nulla RV: nincs frissítés
            rcv_step_mag = sqrt(sum(abs2, rcv_step))    # step hossza
            rcv_step_mag == 0 && continue               # nulla step: nincs irány
            rcv.RV = rcv_step / rcv_step_mag * rcv_rv_mag# új irány: step irányába, eredeti nagysággal. #TODO: ha több forrás is hatással van tgt-re, akkor a forrás osztódik.
        end
    end
end

# Referencia irány (yaw/pitch) alapján horgony beállítása
function update_spherical_position!(distance::Float64, src::Source, world, ref_src::Source, yaw_deg::Float64, pitch_deg::Float64)
    ref_pos = SVector(ref_src.positions[1]...)      # referencia horgony pozíciója (SVector)
    dir = compute_dir(ref_src, yaw_deg, pitch_deg)  # ref RV-hez mért irány (yaw/pitch)
    src.act_p = ref_pos + distance * dir            # új horgony pozíció távolság és irány szerint
    src.act_k = 0                                   # aktuális index reset
    src.positions[1] = Point3d(src.act_p...)        # pálya első pontja a horgonyból
end

# RV irány beállítása; pozíció nem változik
function update_RV_direction!(yaw_deg::Float64, pitch_deg::Float64, src::Source, world, ref_src::Source)
    rv_mag = sqrt(sum(abs2, src.base_RV))           # RV nagyságának megtartása
    dir = compute_dir(ref_src, yaw_deg, pitch_deg)  # új irány számítása yaw/pitch alapján
    src.base_RV = rv_mag * dir                      # irány frissítése; horgony változatlan
    src.RV = src.base_RV
end

# Pozíció alkalmazása: pálya és plot frissítése
function apply_pose!(src::Source, world)
    src.positions = compute_positions(length(src.positions), src, world)  # pálya újragenerálása
    src.plot[:positions][] = src.positions                                # plot frissítése
end

# Forras alapallapot visszaallitasa seek elott
function reset_sources!(world)
    for src in world.sources
        src.RV = src.base_RV
        src.act_p = SVector(src.positions[1]...)
        src.act_k = 0
        src.radii[] = fill(0.0, length(src.radii[]))
        apply_pose!(src, world)
    end
end

# t-re seek: ujraszimulalas 0-tol, step_world! ujrahasznositva
function seek_world_time!(world, target_t::Float64 = world.t[]; step = world.E / 60)
    t_target = target_t
    reset_sources!(world)
    world.t[] = 0.0
    while world.t[] < t_target
        world.t[] += step
        world.t[] > t_target && (world.t[] = t_target)
        step_world!(world; step)
    end
    world.t[] = t_target
end

# RV skálázása; irány megtartása
function apply_RV_rescale!(RV::Float64, src::Source, world)
    u = src.base_RV / sqrt(sum(abs2, src.base_RV))    # irány megtartása: normalizálás és skálázás
    src.base_RV = u * RV                              # skálázott RV beállítása
    src.RV = src.base_RV
    seek_world_time!(world)
end

function apply_RV_direction!(yaw_deg::Float64, pitch_deg::Float64, src::Source, world, ref_src::Source)
    update_RV_direction!(yaw_deg, pitch_deg, src, world, ref_src)
    seek_world_time!(world)
end

function apply_spherical_position!(distance::Float64, src::Source, world, ref_src::Source, yaw_deg::Float64, pitch_deg::Float64)
    update_spherical_position!(distance, src, world, ref_src, yaw_deg, pitch_deg)
    seek_world_time!(world)
end

# UV‑transzform frissítése a forráson
function apply_source_uv!(abscol::Int, src::Source, gctx)
    src.plot[:uv_transform][] = compute_source_uv(abscol, gctx)   # UV transzform beállítása
end

# RR skálár frissítése és 1×3 textúra beállítása (piros–szürke–kék)
function apply_source_RR!(new_RR::Float64, src::Source, world, gctx, abscol::Int)
    src.RR = new_RR                         # RR skálár frissítése
    apply_source_uv!(abscol, src, gctx)     # textúra oszlop frissítése
    seek_world_time!(world)
    return src
end
