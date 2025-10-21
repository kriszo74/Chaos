# ---- source.jl ----

# ForrĂˇs tĂ­pus Ă©s mĹ±veletek â€“ GUIâ€‘fĂĽggetlen logika

# Source: mozgĂˇs Ă©s megjelenĂ­tĂ©si adatok
mutable struct Source
    act_p::SVector{3, Float64}   # aktuĂˇlis pozĂ­ciĂł
    RV::SVector{3, Float64}      # sebessĂ©g vektor
    RR::Float64                  # sajĂˇt tengely kĂ¶rĂĽli szĂ¶gszerĹ± paramĂ©ter (skalĂˇr, fĂ©nysebessĂ©ghez viszonyĂ­thatĂł)
    bas_t::Float64               # indulĂˇsi idĹ‘
    positions::Vector{Point3d}   # pozĂ­ciĂłk (Point3d)
    radii::Observable{Vector{Float64}}  # sugarak puffer
    color::Matrix{RGBAf}         # textĂşra MxN szĂ­nmĂˇtrix (pl. 3x1 RGBAf)
    alpha::Float64               # ĂˇttetszĹ‘sĂ©g
    plot::Any                    # plot handle
end

# add_source!: forrĂˇs hozzĂˇadĂˇsa Ă©s vizuĂˇlis regisztrĂˇciĂł (kĂ¶zvetlen meshscatter! UV-s markerrel Ă©s RR textĂşrĂˇval)
# NOTE: a 'world' tĂ­pust itt sem annotĂˇljuk (kĂ¶rkĂ¶rĂ¶s fĂĽggĂ©s elkerĂĽlĂ©se â€“ World a main.jl-ben).
# LĂ©pĂ©sek: sugarpuffer Ă©s pozĂ­ciĂłsor elĹ‘kĂ©szĂ­tĂ©se â†’ forrĂˇs regisztrĂˇlĂˇsa â†’ UV-s marker + 1Ă—N RRâ€‘textĂşra â†’ instancing.
function add_source!(world, scene, src::Source)
    N = Int(ceil((world.max_t - src.bas_t) * world.density)) # pozĂ­ciĂłk/sugarak elĹ‘kĂ©szĂ­tĂ©se
    src.radii[] = fill(0.0, N)                               # sugarpuffer elĹ‘kĂ©szĂ­tĂ©se N impulzushoz
    src.positions = [Point3d(src.act_p...)]                    # horgony: elsĹ‘ pont a kiindulĂł pozĂ­ciĂł
    src.positions = update_positions(N, src, world)            # kezdeti pozĂ­ciĂłsor generĂˇlĂˇsa aktuĂˇlis RV-vel
    push!(world.sources, src)

     # Marker: latâ€‘long gĂ¶mb UVâ€‘val
    marker_mesh = create_detailed_sphere_fast(Point3f(0, 0, 0), 1f0)

cols = size(src.color, 2)
    col  = min(10, cols)                 # demo: 10. oszlop, ha kevesebb van, akkor az utolsĂł
    u0   = (col - 1) / cols              # offset a 2. (v) komponens mentĂ©n
    sx   = 1f0 / cols                    # oszlopszĂ©lessĂ©g
    uvtr = Makie.uv_transform((Vec2f(0f0, u0 + sx/2), Vec2f(1f0, 0f0)))

    # UV-t tĂĽkrĂ¶zzĂĽk Y-ban, mert a textĂşra sorindexe (0â†’n) a dĂ©liâ†’Ă©szaki irĂˇnyt adta
    ph = meshscatter!(scene, src.positions;
        marker       = marker_mesh,             # UV-s gĂ¶mb marker
        markersize   = src.radii,              # pĂ©ldĂˇnyonkĂ©nti sugĂˇrvektor
        color        = src.color,                    # textĂşra (Matrix{RGBAf})
        uv_transform = uvtr,              # DEMĂ“: atlasz 10. oszlop kivĂˇgĂˇsa
        rotation     = Vec3f(0.0, pi/4, 0.0),  # (Ăşj)) radiĂˇn (x, y, z) TODO: mesh mĂłdosĂ­tĂˇsa, hogy ne kelljen alaprotĂˇciĂł.
        transparency = true,                   # ĂˇtlĂˇtszĂłsĂˇg engedĂ©lyezve
        alpha        = src.alpha,              # ĂˇtlĂˇtszĂłsĂˇg mĂ©rtĂ©ke
        interpolate  = true,                   # (Ăşj) textĂşrainterpolĂˇciĂł bekapcsolva
        shading      = true)                   # (Ăşj) fĂ©ny-ĂˇrnyĂ©k aktĂ­v

    src.plot = ph
    return src
end

# SugĂˇrvektor frissĂ­tĂ©se adott t-nĂ©l; meglĂ©vĹ‘ pufferbe Ă­r, aktĂ­v [1:K], a tĂ¶bbi 0.
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

# PozĂ­ciĂłk ĂşjragenerĂˇlĂˇsa adott N alapjĂˇn
function update_positions(N::Int, src::Source, world)
    dp = src.RV / world.density            # kĂ©t impulzus kĂ¶zti eltolĂˇs
    return [Point3d((src.positions[1] + dp * k)...) for k in 0:N-1]
end

# IdĹ‘ szerinti vizuĂˇlis Ăˇllapot alkalmazĂˇsa (scrub/play)
# Csak a sugarakat frissĂ­ti a world.t alapjĂˇn. KĂ©sĹ‘bb bĹ‘vĂ­thetĹ‘ a pozĂ­ciĂłkra is.
function apply_time!(world)
    @inbounds for src in world.sources
        src.radii[] = update_radii(src.radii[], src.bas_t, world.t[], world.density)
    end
end

# RV skĂˇlĂˇr frissĂ­tĂ©se + positions ĂşjragenerĂˇlĂˇsa (irĂˇny megtartĂˇsa)
# ParamĂ©terek: RV (nagysĂˇg), src (forrĂˇs), world (vilĂˇgĂˇllapot)
function update_source_RV(RV::Float64, src::Source, world)
    # irĂˇny megtartĂˇsa: pitch=90Â°, distance=0, yaw=0 â†’ dir == u
    _, src.RV = calculate_coordinates(world, src, RV, 0.0, 0.0, 90.0)
    src.plot[:positions][] = src.positions = update_positions(length(src.positions), src, world)
end

# UV oszlop indexbĹ‘l uv_transform frissĂ­tĂ©se
function update_source_uv!(abscol::Int, src::Source, gctx)
    u0 = Float32((abscol - 1) / gctx.cols)  # 1-alapĂş oszlop â†’ u offset
    sx = 1f0 / Float32(gctx.cols)           # egy oszlop szĂ©lessĂ©ge u-ban
    uvtr = Makie.uv_transform((Vec2f(0f0, u0 + sx/2), Vec2f(1f0, 0f0)))
    src.plot[:uv_transform][] = uvtr
end

# RR skĂˇlĂˇr frissĂ­tĂ©se Ă©s 1Ă—3 textĂşra beĂˇllĂ­tĂˇsa (pirosâ€“szĂĽrkeâ€“kĂ©k)
function update_source_RR(new_RR::Float64, src::Source, gctx, abscol::Int)
    src.RR = new_RR
    update_source_uv!(abscol, src, gctx)
    return src
end

# KoordinĂˇtĂˇk szĂˇmĂ­tĂˇsa referenciakĂ©nt adott src alapjĂˇn
# - src == nothing â†’ pos=(0,0,0), RV_vec=(RV,0,0)
# - kĂĽlĂ¶nben a src aktuĂˇlis akt_p/RV Ă©rtĂ©keihez kĂ©pest yaw/pitch szerint szĂˇmol
function calculate_coordinates(world,
                               src::Union{Nothing,Source},
                               RV::Float64,
                               distance::Float64,
                               yaw_deg::Float64,
                               pitch_deg::Float64)
    isnothing(src) && return SVector(0.0, 0.0, 0.0), SVector(RV, 0.0, 0.0)
    ref_pos = src.act_p
    ref_RV  = src.RV

    # u: ref_RV irĂˇny egysĂ©gvektor
    u = ref_RV / sqrt(sum(abs2, ref_RV))
    # stabil referencia a merĹ‘leges bĂˇzishoz
    refz = SVector(0.0, 0.0, 1.0); refy = SVector(0.0, 1.0, 0.0)
    refv = abs(sum(refz .* u)) > 0.97 ? refy : refz
    # sĂ­kbĂˇzis ref_RV-re merĹ‘legesen
    e2p = refv - (sum(refv .* u)) * u
    e2  = e2p / sqrt(sum(abs2, e2p))
    e3  = SVector(u[2]*e2[3]-u[3]*e2[2], u[3]*e2[1]-u[1]*e2[3], u[1]*e2[2]-u[2]*e2[1]) # u Ă— e2

    # fok â†’ radiĂˇn
    yaw   = yaw_deg   * (pi/180)
    pitch = pitch_deg * (pi/180)

    # irĂˇnyvektor yaw/pitch szerint (pitch 0Â° = Î â‚€, +pitch az u felĂ©)
    dir = cos(pitch)*cos(yaw)*e2 + cos(pitch)*sin(yaw)*e3 + sin(pitch)*u
    dir = dir / sqrt(sum(abs2, dir))

    pos    = ref_pos + distance * dir
    RV_vec = RV * dir
    return pos, RV_vec
end

