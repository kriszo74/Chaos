# Forrás entitás és alap műveletek: pozíció, RV/irány, megjelenítés.
# GUI‑független, KISS utilok és állapotkezelés (regen+plot, UV).
# Spherical pozicionálás (distance/yaw/pitch) és compute_dir alapú irányszámítás.
#TODO: a függvények szignatúrájának felülvizsgálása, legyen egy logikus sorrend.

const SOURCE_UV_T = typeof(Makie.uv_transform((Vec2f(0f0, 0f0), Vec2f(1f0, 0f0))))
const SOURCE_UV_ID = Makie.uv_transform((Vec2f(0f0, 0.5f0), Vec2f(1f0, 0f0)))
const ALPHA_VALUES_F32 = Float32.(CFG["gui"]["ALPHA_VALUES"])
const ALPHA_VALUES_COUNT = length(ALPHA_VALUES_F32)

# Source: mozgás és megjelenítési adatok
mutable struct Source
    act_p::SVector{3, Float64}   # aktuális pozíció
    act_k::Int                   # aktuális index
    RV_u::SVector{3, Float64}    # aktuális RV irányegységvektor
    base_RV_u::SVector{3, Float64} # alap RV irányegységvektor (seek resethez)
    RV_mag::Float64              # RV abszolútérték
    RR::Float64                  # saját tengely körüli szögszerű paraméter (skalár, fénysebességhez viszonyítható)
    bas_t::Float64               # indulási idő
    anch_p::SVector{3, Float64}  # pálya horgony pozíciója
    range::UnitRange{Int}        # közös puffer index-tartomány
    uv_transform::SOURCE_UV_T    # UV transzform
    uv_alpha_bank::Vector{SOURCE_UV_T} # UV bank a fade szintekhez
    fade_ratio_edges::Vector{Float64}  # fade arány-határok
    fade_radius_breaks::Vector{Float64}# konkrét sugár-határok
    max_fade_ix::Int
end

# forrás hozzáadása és vizuális regisztráció (közvetlen meshscatter! UV-s markerrel és RR textúrával)
function add_source!(world, cols::Int, spec; sel_col::Int)
    uv_alpha_bank = compute_source_uvs(sel_col, cols, spec.fade_ratio_edges)
    src = Source(
        SVector(0.0, 0.0, 0.0),                 # aktuális pozíció
        0,                                      # aktuális index
        SVector(1.0, 0.0, 0.0),                 # kezdő RV egységvektor
        SVector(1.0, 0.0, 0.0),                 # alap RV egységvektor
        spec.RV,                                # RV abszolútérték
        spec.RR,                                # saját tengely körüli RR
        0.0,                                    # indulási idő
        SVector(0.0, 0.0, 0.0),                 # pálya horgony pozíciója
        1:0,                                    # közös puffer szelet (üres)
        uv_alpha_bank[1],                       # UV‑atlasz oszlop kiválasztása
        uv_alpha_bank,                          # UV alpha bank
        Float64.(spec.fade_ratio_edges),        # fade arány-határok
        Float64[],                              # konkrét sugár-határok
        1)

    if spec.ref !== nothing
        ref_src = world.sources[spec.ref]
        update_spherical_position!(spec, src, ref_src)
        update_RV_direction!(spec, src, ref_src)
    end

    build_source!(world, src)                    # forrás puffereinek felépítése
    push!(world.sources, src)                    # forrás regisztrálása a listában
    return src
end

# közös pufferek bővítése és forrás tartományának kiosztása
function build_source!(world, src)
    N = Int(ceil((world.max_t - src.bas_t) * world.density)) + 1 # pozíciók/sugarak előkészítése
    start_ix = world.next_start_ix                           # közös puffer kezdő index
    world.next_start_ix = start_ix + N                       # következő forrás kezdő indexe
    src.range = start_ix:world.next_start_ix -1              # forrás szelet a közös pufferekben
    rebuild_source_fade_breaks!(src, world)                  # arányhatárok sugárra fordítva

    append!(world.positions_all, compute_positions(N, src, world)) # kezdeti pozíciósor, aktuális RV-vel a közös pufferhez
    append!(world.radii_all[], fill(0.0, N))                 # sugárértékek hozzáfűzése
    append!(world.uv_all[], fill(src.uv_transform, N))       # UV puffer bővítése alap transzformmal
end

# Sugarak frissítése a world.t alapján
# TODO: CUDA.jl: radii batch futtatása GPU-n (több forrás, szegmensek)
function step_world!(world; step = world.E / 60)
    update_radii!(world)  # sugárpuffer frissítése
    apply_wave_hit!(world)
    for src in world.sources
        src.act_p += src.RV_u * src.RV_mag * step
        world.positions_all[first(src.range) + src.act_k] = Point3d(src.act_p...)
    end
    world.plot[:positions][] = world.positions_all
end

# Irányvektor a ref RV tengelyéhez mérve (yaw/pitch)
const REFZ = SVector(0.0, 0.0, 1.0) # stabil referencia vektor
const REFY = SVector(0.0, 1.0, 0.0) # stabil referencia vektor
function compute_dir(ref_src::Source, yaw::Float64, pitch::Float64)
    u = ref_src.base_RV_u                      # ref RV irányegység
    refv = abs(sum(REFZ .* u)) > 0.97 ? REFY : REFZ # fallback, ha közel párhuzamos
    e2p = refv - (sum(refv .* u)) * u          # u-ra merőleges komponens
    e2  = e2p / sqrt(sum(abs2, e2p))           # normalizált e2
    e3  = SVector(u[2]*e2[3]-u[3]*e2[2], u[3]*e2[1]-u[1]*e2[3], u[1]*e2[2]-u[2]*e2[1]) # e3 = u × e2
    sy, cy = sincos(yaw)                       # yaw szinusz és koszinusz
    sp, cp = sincos(pitch)                     # pitch szinusz és koszinusz
    dir = cp*cy*e2 + cp*sy*e3 + sp*u           # irány komponensek
    return dir / sqrt(sum(abs2, dir))          # egységvektor visszaadása
end

# Pozíciók újragenerálása adott N alapján
# TODO: CUDA.jl: pályapontok generálása GPU-n; visszamásolás minimalizálása
function compute_positions(N::Int, src::Source, world)
    dp = src.RV_u * src.RV_mag / world.density                       # két impulzus közti pozíciólépés
    return [Point3d((src.anch_p + dp * k)...) for k in 0:N-1]        # pálya N ponttal
end

# közös forráspufferek alapállapotba visszaállítása
function clear_sources_buffers!(world)
    empty!(world.positions_all)     # pozíciópuffer ürítése
    world.radii_all[] = Float64[]   # sugárpuffer ürítése
    world.uv_all[] = SOURCE_UV_T[]  # UV puffer ürítése
    world.next_start_ix = 1         # indexszámláló visszaállítása
end

# Pufferhosszak frissítése density/max_t változásnál
function update_sampling!(world)
    clear_sources_buffers!(world)   # pufferek újraépítés előtti nullázása
    for src in world.sources
        build_source!(world, src)       # új mintavételezésű puffer-szelet építése
    end
    seek_world_time!(world, recompute = false)
end

# UV bank készítése a kiválasztott oszlopból, egymást követő alpha oszlopokkal
function compute_source_uvs(sel_col::Int, cols::Int, fade_ratio_edges)
    sx = 1f0 / Float32(cols)                                        # oszlopszélesség

    # DEBUG kód
    # uvs = Vector{SOURCE_UV_T}(undef, length(fade_ratio_edges))
    # for i in eachindex(fade_ratio_edges)
    #     #uv = Makie.uv_transform((Vec2f(0f0, (sel_col - length(fade_ratio_edges) + i - 1) / cols + sx / 2), Vec2f(1f0, 0f0)))
    #     uv = Makie.uv_transform((Vec2f(0f0, (sel_col - i + 1) / cols + sx / 2), Vec2f(1f0, 0f0)))
    #     uvs[i] = uv
    # end
    # if length(uvs) > 1
    #     @info "sel_col: $sel_col, uvs: $(uvs[1][8]), $(uvs[2][8]) ,$(uvs[3][8]), $(uvs[4][8]), $(uvs[5][8])"
    # else 
    #     @info "sel_col: $sel_col, uvs: $(uvs[1])"
    # end
    #return uvs
    return [Makie.uv_transform((Vec2f(0f0, (sel_col - i + 1) / cols + sx / 2), Vec2f(1f0, 0f0))) for i in eachindex(fade_ratio_edges)]
end

# Emanáció implementálása: sugárvektor frissítése adott t-nél; meglévő pufferbe ír, aktív [1:K], a többi 0.
# TODO: CUDA.jl: CuArray + egykernelű frissítés nagy N esetén
function update_radii!(world)
    @inbounds for src in world.sources # források bejárása
        rg = src.range                                  # forrás tartomány
        radii = @view world.radii_all[][rg]             # sugárpuffer
        uvs = @view world.uv_all[][rg]                  # UV puffer
        dt_rel = (world.t[] - src.bas_t)                # relatív idő az indulástól
        K = ceil(Int, round(dt_rel * world.density, digits = 8)) # aktív sugarak száma TODO: OOB veszélyt kezelni / mérésekkel igazolni, hogy ez gyorsabb és megfontolni a haszálatát: K = min(ceil(Int, dt_rel * world.density), length(radii))
        src.act_k = K                                   # aktuális index
        for i in 1:K                                    # aktív szegmensek frissítése
            radii[i] = r = dt_rel - (i-1) / world.density         # sugár idő az i. impulzushoz
            uvs[i] = src.uv_alpha_bank[searchsortedlast(src.fade_radius_breaks, r)]
        end
    end
    notify(world.radii_all)
    notify(world.uv_all)
end

# Realizáció vizsgálat: kifelé igazítja rcv (receiver, azaz realizáló forrás) RV-jét.
function apply_wave_hit!(world)
    for emt in world.sources
        emt_radii = @view world.radii_all[][emt.range] # emmiter (emt) sugárpuffer pillanatképe
        for rcv in world.sources                # ütközésvizsgálat minden forrásra (self is)
            emt_k = 0; min_gap2 = typemax(Float64); r2_min_emt = to_rcv2 = 0.0; emt_p = to_rcv = SVector(0.0, 0.0, 0.0);
            @inbounds for erix in eachindex(emt_radii)  # erix: Emmitter (emt) Radius (radii) IndeX
                r_erix = emt_radii[erix]        # aktuális emitter impulzus sugara
                r_erix == 0 && break            # az első 0 után a maradék is inaktív, kilépünk a ciklusból
                
                # r^2 és célpont távolság^2 különbség számítása
                r2_erix = r_erix * r_erix               # a vizsgált emitter impulzus sugárának négyzete
                p_erix  = SVector(world.positions_all[first(emt.range) + erix - 1]...)   # a vizsgált emitter impulzus középpontja
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
            # TODO: számold a relatív sebesség radiális komponensét, és ha kifelé megy (dot(to_rcv_u, rcv.RV_u * rcv.RV_mag) ≥ 0), akkor continue; így csak befelé haladva érvényesül az impulzus.

            # ütközés történt, to_tgt egységvektorának meghatározása
            to_rcv_u, _ = unit_and_mag(to_rcv); isnothing(to_rcv_u) && continue # to_tgt egységvektora TODO: input oldalon tiltani a 0 távolságot és ütköző yaw/pitch kombinációkat

            # kiszámítjuk aktuális impulzushoz (p) tartozó forrás (src) RV-jének egységvektorát.
            emt_rv_dir = SVector(world.positions_all[first(emt.range) + emt_k]...) - emt_p # src.RV irányvektora TODO: unit teszttel igazolni, hogy nem fut OOB-ra.
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
            rcv_step = (rcv.RV_u * rcv.RV_mag + emt_v + emt_rot) / world.density # ez az eredő vektor, ezt kell hozzáadni rcv.positions[k]-hoz
            rcv_step_mag = sqrt(sum(abs2, rcv_step))    # step hossza
            rcv_step_mag == 0 && continue               # nulla step: nincs irány #TODO: bebizonyítani, hogy ez nem lehetséges és kivenni a guardot!
            rcv.RV_u = rcv_step / rcv_step_mag          # új irány: step irányába, eredeti nagysággal. #TODO: ha több forrás is hatással van tgt-re, akkor a forrás osztódik.
        end
    end
end

# Referencia irány (yaw/pitch) alapján horgony beállítása
function update_spherical_position!(spec, src::Source, ref_src::Source)
    ref_pos = ref_src.anch_p                        # referencia horgony pozíciója (SVector)
    dir = compute_dir(ref_src, spec.yaw, spec.pitch)# ref RV-hez mért irány (yaw/pitch)
    src.act_p = ref_pos + spec.distance * dir       # új horgony pozíció távolság és irány szerint
    src.anch_p = src.act_p                          # horgony frissítése
    src.act_k = 0                                   # aktuális index reset
end

# RV irány beállítása; pozíció nem változik
function update_RV_direction!(spec, src::Source, ref_src::Source)
    dir = compute_dir(ref_src, spec.rv_yaw, spec.rv_pitch) # új irány számítása yaw/pitch alapján
    src.base_RV_u = dir                             # irány frissítése; horgony változatlan
    src.RV_u = src.base_RV_u
end

# t-re seek: ujraszimulalas 0-tol, step_world! ujrahasznositva
function seek_world_time!(world, target_t::Float64 = world.t[]; step = world.E / 60, recompute = true)
    for src in world.sources
        src.RV_u = src.base_RV_u # irány visszaállítása alapértékre
        src.act_p = src.anch_p   # aktuális pozíció visszaállítása horgonyra
        src.act_k = 0            # aktuális sugárindex nullázása
        if recompute             # pályapuffer újragenerálása, ha szükséges
            world.positions_all[src.range] = compute_positions(length(src.range), src, world) 
        end 
    end

    t_limit = target_t - step + eps_tol         # utolsó teljes szimulációs lépés felső korlátja
    fill!(world.radii_all[], 0.0)               # sugárpuffer teljes nullázása
    t_limit <= 0.0 && notify(world.radii_all)   # sugárpuffer változásának jelzése

    world.t[] = 0.0
    while world.t[] < t_limit
        world.t[] += step
        step_world!(world; step)    # világállapot léptetése és kirajzolása
    end
    world.t[] = target_t
end

# RV skálázása; irány megtartása
function apply_RV_rescale!(RV::Float64, src::Source, world)
    src.RV_mag = RV                                   # skálázott RV beállítása
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

# fade arány-határokból konkrét sugár-határok építése
function rebuild_source_fade_breaks!(src::Source, world)
    src.fade_radius_breaks = [((length(src.range) - 1) / world.density) * r for r in src.fade_ratio_edges]
end

# UV‑transzformok és fade lookup újraépítése a forráson
function apply_source_uv!(sel_col::Int, src::Source, cols::Int, world)
    src.uv_alpha_bank = compute_source_uvs(sel_col, cols, src.fade_ratio_edges) # fade szintek UV bankja
    update_radii!(world)
end

# RR skálár frissítése és 1×3 textúra beállítása (piros–szürke–kék)
function apply_source_RR!(new_RR::Float64, src::Source, world, cols::Int, sel_col::Int)
    src.RR = new_RR                              # RR skálár frissítése
    src.uv_alpha_bank = compute_source_uvs(sel_col, cols, src.fade_ratio_edges)  # textúra oszlop frissítése
    seek_world_time!(world)
end
