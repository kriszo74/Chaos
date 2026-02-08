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
    
    # futás-optimalizációs változók:
    radii_clear_needed::Bool     # radii nullázás jelző
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
        nothing,                                # plot handle kezdetben üres
        true)                                   # radii nullázás jelző
    
    if spec.ref !== nothing
        ref_src = world.sources[spec.ref]
        update_spherical_position!(spec, src, ref_src)
        update_RV_direction!(spec, src, ref_src)
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
const REFZ = SVector(0.0, 0.0, 1.0) # stabil referencia vektor
const REFY = SVector(0.0, 1.0, 0.0) # stabil referencia vektor
function compute_dir(ref_src::Source, yaw::Float64, pitch::Float64)
    ref_RV = ref_src.base_RV                   # referencia RV vektora
    u = ref_RV / sqrt(sum(abs2, ref_RV))       # ref RV irányegység
    refv = abs(sum(REFZ .* u)) > 0.97 ? REFY : REFZ                # fallback, ha közel párhuzamos
    e2p = refv - (sum(refv .* u)) * u          # u-ra merőleges komponens
    e2  = e2p / sqrt(sum(abs2, e2p))           # normalizált e2
    e3  = SVector(u[2]*e2[3]-u[3]*e2[2], u[3]*e2[1]-u[1]*e2[3], u[1]*e2[2]-u[2]*e2[1])  # e3 = u × e2
    sy, cy = sincos(yaw)                       # yaw szinusz és koszinusz
    sp, cp = sincos(pitch)                     # pitch szinusz és koszinusz
    dir = cp*cy*e2 + cp*sy*e3 + sp*u           # irány komponensek
    return dir / sqrt(sum(abs2, dir))          # egységvektor visszaadása
end

# Pozíciók újragenerálása adott N alapján
# TODO: CUDA.jl: pályapontok generálása GPU-n; visszamásolás minimalizálása
function compute_positions(N::Int, src::Source, world)
    dp = src.RV / world.density                                      # két impulzus közti pozíciólépés
    return [Point3d((src.positions[1] + dp * k)...) for k in 0:N-1]  # pálya N ponttal
end

# Pufferhosszak frissítése density/max_t változásnál
function update_sampling!(world)
    for src in world.sources
        N = Int(ceil((world.max_t - src.bas_t) * world.density))
        src.radii[] = fill(0.0, N)
        src.positions = compute_positions(N, src, world)
        src.plot[:positions][] = src.positions
        src.radii_clear_needed = true
    end
end

# UV oszlop indexből uv_transform kiszámítása
function compute_source_uv(abscol::Int, gctx)
    u0 = Float32((abscol - 1) / gctx.cols)                          # oszlop kezdő U koordináta
    sx = 1f0 / Float32(gctx.cols)                                   # oszlopszélesség
    return Makie.uv_transform((Vec2f(0f0, u0 + sx/2), Vec2f(1f0, 0f0))) # UV eltolás + skálázás
end

# Emanáció implementálása: sugárvektor frissítése adott t-nél; meglévő pufferbe ír, aktív [1:K], a többi 0.
# TODO: CUDA.jl: CuArray + egykernelű frissítés nagy N esetén
function update_radii!(world)
    @inbounds for src in world.sources # források bejárása
        radii = src.radii[]                         # sugárpuffer
        dt_rel = (world.t[] - src.bas_t)            # relatív idő az indulástól
        K = ceil(Int, round(dt_rel * world.density, digits = 12)) # aktív sugarak száma TODO: mérésekkel igazolni, hogy ez gyorsabb és megfontolni a haszálatát: K = min(ceil(Int, dt_rel * world.density), length(radii))
        src.act_k = K                               # aktuális index
        @inbounds begin
            for i in 1:K                            # aktív szegmensek frissítése
                radii[i] = r = dt_rel - (i-1) / world.density   # sugár idő az i. impulzushoz
            end
            if src.radii_clear_needed
                N = length(radii)                       # pufferhossz
                K < N && fill!(view(radii, K+1:N), 0.0) # inaktív szakasz nullázása: csak első futásnál és visszatekerésnél szükséges.
                src.radii_clear_needed = false
            end
        end
        src.radii[] = radii             # sugárpuffer frissítése
    end
end

# Realizáció vizsgálat: kifelé igazítja rcv (receiver, azaz realizáló forrás) RV-jét.
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
            emt_rv_u, emt_rv_dir_mag = unit_and_mag(emt_rv_dir) # src.RV egységvektora és hossza

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
            rcv_step_mag = sqrt(sum(abs2, rcv_step))    # step hossza
            rcv_step_mag == 0 && continue               # nulla step: nincs irány #TODO: bebizonyítani, hogy ez nem lehetséges és kivenni a guardot!
            rcv.RV = rcv_step / rcv_step_mag * rcv_rv_mag# új irány: step irányába, eredeti nagysággal. #TODO: ha több forrás is hatással van tgt-re, akkor a forrás osztódik.
        end
    end
end

# Referencia irány (yaw/pitch) alapján horgony beállítása
function update_spherical_position!(spec, src::Source, ref_src::Source)
    ref_pos = SVector(ref_src.positions[1]...)      # referencia horgony pozíciója (SVector)
    dir = compute_dir(ref_src, spec.yaw, spec.pitch) # ref RV-hez mért irány (yaw/pitch)
    src.act_p = ref_pos + spec.distance * dir       # új horgony pozíció távolság és irány szerint
    src.act_k = 0                                   # aktuális index reset
    src.positions[1] = Point3d(src.act_p...)        # pálya első pontja a horgonyból
end

# RV irány beállítása; pozíció nem változik
function update_RV_direction!(spec, src::Source, ref_src::Source)
    rv_mag = sqrt(sum(abs2, src.base_RV))           # RV nagyságának megtartása
    dir = compute_dir(ref_src, spec.rv_yaw, spec.rv_pitch) # új irány számítása yaw/pitch alapján
    src.base_RV = rv_mag * dir                      # irány frissítése; horgony változatlan
    src.RV = src.base_RV
end

# Pozíció alkalmazása: pálya és plot frissítése
function apply_pose!(src::Source, world)
    src.positions = compute_positions(length(src.positions), src, world)  # pálya újragenerálása
    src.plot[:positions][] = src.positions                                # plot frissítése
end

# t-re seek: ujraszimulalas 0-tol, step_world! ujrahasznositva
function seek_world_time!(world, target_t::Float64 = world.t[]; step = world.E / 60)
    for src in world.sources
        src.RV = src.base_RV
        src.act_p = SVector(src.positions[1]...)
        src.act_k = 0
        src.radii[] = fill(0.0, length(src.radii[]))
        apply_pose!(src, world)
        src.radii_clear_needed = true
    end

    world.t[] = 0.0
    t_limit = target_t - step + eps_tol
    while world.t[] < t_limit
        world.t[] += step
        step_world!(world; step)
    end
    world.t[] = target_t
end

# RV skálázása; irány megtartása
function apply_RV_rescale!(RV::Float64, src::Source, world)
    u = src.base_RV / sqrt(sum(abs2, src.base_RV))    # irány megtartása: normalizálás és skálázás
    src.base_RV = u * RV                              # skálázott RV beállítása
    src.RV = src.base_RV
    seek_world_time!(world)
end

function apply_RV_direction!(spec, src::Source, world)
    update_RV_direction!(spec, src, world.sources[spec.ref])
    seek_world_time!(world)
end

function apply_spherical_position!(spec, src::Source, world)
    update_spherical_position!(spec, src, world.sources[spec.ref])
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
