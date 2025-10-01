# ---- source.jl ----

# Forrás típus és műveletek – GUI‑független logika

# Source: mozgás és megjelenítési adatok
# %% START ID=SOURCE_TYPE, v1
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
# %% END ID=SOURCE_TYPE

# %% START ID=ADD_SOURCE, v2
# add_source!: forrás hozzáadása és vizuális regisztráció (közvetlen meshscatter! UV-s markerrel és RR textúrával)
# NOTE: a 'world' típust itt sem annotáljuk (körkörös függés elkerülése – World a main.jl-ben).
# Lépések: sugarpuffer és pozíciósor előkészítése → forrás regisztrálása → UV-s marker + 1×N RR‑textúra → instancing.
#= function add_source!(world, scene, src::Source)
    N = Int(ceil((world.max_t - src.bas_t) * world.density)) # pozíciók/sugarak előkészítése
    src.radii[] = fill(0.0, N)                               # sugarpuffer előkészítése N impulzushoz
    src.positions = [Point3d(src.act_p...)]                  # horgony: első pont a kiinduló pozíció
    src.positions = update_positions(N, src, world)          # kezdeti pozíciósor generálása aktuális RV-vel
    push!(world.sources, src)
    # RR orientáció (egység irányvektor az RV-ből)
    rv = src.RV
    len = sqrt(sum(abs2, rv))
    omega_dir = len > 0 ? Makie.Vec3f(Float32(rv[1]/len), Float32(rv[2]/len), Float32(rv[3]/len)) : Makie.Vec3f(1,0,0)
    # UV-s marker + 1×N RR textúra (latitude BWR)
    marker = create_detailed_sphere(Point3f(0,0,0), 1f0, 48)
    tex    = rr_texture_for(src.color; rr_scalar=Float32(src.RR))
    ph = meshscatter!(scene, src.positions;
        marker       = marker,
        markersize   = src.radii,
        color        = tex,           # TEXTÚRA
        uv_transform = :flip_y,       # latitude-textúra helyes állása
        transparency = true,
        alpha        = src.alpha)
    src.plot = ph
    return src
end =#
function add_source!(world, scene, src::Source)
    N = Int(ceil((world.max_t - src.bas_t) * world.density)) # pozíciók/sugarak előkészítése
    src.radii[] = fill(0.0, N)                               # sugarpuffer előkészítése N impulzushoz
    src.positions = [Point3d(src.act_p...)]                    # horgony: első pont a kiinduló pozíció
    src.positions = update_positions(N, src, world)            # kezdeti pozíciósor generálása aktuális RV-vel
    push!(world.sources, src)

    # RR orientáció (egység irányvektor az RV-ből)
    rv = src.RV; len = sqrt(sum(abs2, rv))
    omega_dir = len > 0 ? Makie.Vec3f(Float32(rv[1]/len), Float32(rv[2]/len), Float32(rv[3]/len)) : Makie.Vec3f(1,0,0)
    rr = RRParams(omega_dir=omega_dir, RR_scalar=Float32(src.RR));
    
    # Kamera nézőiránya (ortografikus setup_scene szerint): V = (0,0,-1)
    V = Vec3f(0, 0, -1)    

    # Equator‑orientált tengely: a marker Z‑je legyen ⟂ V, hogy az egyenlítő mindig látszódjon
    axis = equator_facing_axis(rr.omega_dir, V)

    # Marker: lat‑long gömb UV‑val
    marker_mesh = create_detailed_sphere(Point3f(0, 0, 0), 1f0)

    # Textúra: szélességi alapú kék→fehér→vörös (északi→egyenlítő→déli)
    tex = rr_texture_for(:cyan;
        palette   = :classic,
        pos_color = :blue,
        neg_color = :red,
        n         = 512,
        rr_scalar = rr.beta_max * 0.99f0, # fix, közel max hatás
        beta_max  = rr.beta_max,
        h_max_deg = rr.h_max_deg,
        desat_mid = rr.desat_mid)

    # UV-t tükrözzük Y-ban, mert a textúra sorindexe (0→n) a déli→északi irányt adta
    ph = meshscatter!(scene, src.positions;
        marker        = marker_mesh,
        markersize    = src.radii,
        color         = tex,            # << textúra (Matrix{RGBAf})
        uv_transform  = :flip_y,        # <<< ettől Észak felül = kék, Dél alul = vörös
        rotation      = axis,           # z‑tengely az equator‑orientált irányba
        transparency  = true,
        alpha         = src.alpha,
        interpolate   = true,
        shading       = false)          # <<< egységes szín a szélességi körök mentén
    src.plot = ph
    return src
end
# %% END ID=ADD_SOURCE

# %% START ID=UPDATE_RADII, v1
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
# %% END ID=UPDATE_RADII

# %% START ID=UPDATE_POSITIONS, v1
# Pozíciók újragenerálása adott N alapján
function update_positions(N::Int, src::Source, world)
    dp = src.RV / world.density            # két impulzus közti eltolás
    return [Point3d((src.positions[1] + dp * k)...) for k in 0:N-1]
end
# %% END ID=UPDATE_POSITIONS

# %% START ID=APPLY_TIME, v1
# Idő szerinti vizuális állapot alkalmazása (scrub/play)
# Csak a sugarakat frissíti a world.t alapján. Később bővíthető a pozíciókra is.
function apply_time!(world)
    @inbounds for src in world.sources
        src.radii[] = update_radii(src.radii[], src.bas_t, world.t[], world.density)
    end
end
# %% END ID=APPLY_TIME

# %% START ID=UPDATE_SOURCE_RV, v1
# RV skálár frissítése + positions újragenerálása (irány megtartása)
# Paraméterek: RV (nagyság), src (forrás), world (világállapot)
function update_source_RV(RV::Float64, src::Source, world)
    # irány megtartása: pitch=90°, distance=0, yaw=0 → dir == u
    _, src.RV = calculate_coordinates(world, src, RV, 0.0, 0.0, 90.0)
    src.plot[:positions][] = src.positions = update_positions(length(src.positions), src, world)
end
# %% END ID=UPDATE_SOURCE_RV

# %% START ID=CALC_COORDS, v1
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
# %% END ID=CALC_COORDS

