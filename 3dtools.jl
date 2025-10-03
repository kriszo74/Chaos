# ---- 3dtools.jl ----

# Színkezeléshez használjuk a Colors csomagot (Makie függősége)
using Colors
using Makie, GLMakie
using GeometryBasics: Point3f, GLTriangleFace, Sphere
using LinearAlgebra: norm, normalize, dot, cross, I

# Gömbfelület generálása egyetlen hívással (GeometryBasics helper)
# center  – a gömb közepe
# radius  – sugár
# res     – θ és φ irányú felbontás (≥ 3)
function create_detailed_sphere_fast(center::Point3f, r::Float32, res::Int=48)
    @assert res ≥ 8 "res should be ≥ 8 for smooth markers"
    # Lat–long rács: előallokáció + előre számolt sincos → kevesebb allokáció, gyorsabb
    nlats = res
    nlons = 2*res
    W     = nlons + 1
    Nv    = (nlats + 1) * W              # vertex/uv/normal darabszám
    Nt    = 2 * nlats * nlons            # háromszög darabszám

    verts  = Vector{Point3f}(undef, Nv)
    uvs    = Vector{Vec2f}(undef, Nv)
    faces  = Vector{GLTriangleFace}(undef, Nt)

    # φ ∈ [0, π], θ ∈ [0, 2π]
    φ = collect(range(0f0, stop=Float32(pi),       length=nlats+1))
    θ = collect(range(0f0, stop=2f0*Float32(pi),   length=nlons+1))

    sφ = similar(φ); cφ = similar(φ)
    sθ = similar(θ); cθ = similar(θ)

    @inbounds @simd for i in eachindex(φ)
        sφ[i], cφ[i] = sincos(φ[i])
    end
    @inbounds @simd for j in eachindex(θ)
        sθ[j], cθ[j] = sincos(θ[j])
    end

    # Vertex + UV táblázat feltöltése indexeléssel (push! nélkül)
    @inbounds for i in 0:nlats
        z = cφ[i+1]; s = sφ[i+1]
        v = Float32(1 - i/nlats)
        rowoff = i * W
        @simd for j in 0:nlons
            x = s * cθ[j+1]; y = s * sθ[j+1]
            u = Float32(j/nlons)
            idx = rowoff + j + 1
            verts[idx] = Point3f(center .+ r .* Vec3f(x, y, z))
            uvs[idx]   = Vec2f(u, v)
        end
    end

    # Háromszögarcok
    k = 0
    @inbounds for i in 1:nlats, j in 1:nlons
        a = (i-1)*W + j
        b = a + 1
        c = a + W
        d = c + 1
        k += 1; faces[k] = GLTriangleFace(a, c, b)
        k += 1; faces[k] = GLTriangleFace(b, c, d)
    end

    # Normálok: sugárirány (v - center)/r
    normals = Vector{Vec3f}(undef, Nv)
    @inbounds @simd for idx in 1:Nv
        v = Vec3f(verts[idx]) - Vec3f(center)
        normals[idx] = v / r
    end

    return GeometryBasics.Mesh((position = verts, normal = normals, uv = uvs), faces)
end

# ÚJ: RR colormap helyőrző (egyelőre egyszínű – cyan)
# RR colormap – egyelőre a wrapper nem használja, de itt készítjük elő a kétoldali skálát
# Megjegyzés: jelenleg a render még egyszínű; később a shader ezt fogja használni.

# Hue-eltolás + (enyhe) deszaturálás HSV-ben
@inline function _hsv_shift_rgba(c::RGBAf, Δh_deg::Float32, sat_scale::Float32)
    rgb = RGB(c.r, c.g, c.b)
    hsv = HSV(rgb)
    h   = mod(hsv.h + Δh_deg/360f0, 1f0)
    s   = clamp(hsv.s * sat_scale, 0f0, 1f0)
    v   = hsv.v
    rgb2 = RGB(HSV(h, s, v))
    return RGBAf(Float32(rgb2.r), Float32(rgb2.g), Float32(rgb2.b), alpha(c))
end

"""
make_rr_colormap(base::RGBAf; h_max_deg=120f0, desat_mid=0.15f0, n::Int=256)
  Kétoldali (−→+) gradienst készít egy alapszínből úgy, hogy a közép kissé
  deszaturált, a szélek visszanyerik a telítettséget.
"""
function make_rr_colormap(base::RGBAf; h_max_deg=120f0, desat_mid=0.15f0, n::Int=256)
    n ≤ 2 && return [base, base]
    out = Vector{RGBAf}(undef, n)
    for i in 1:n
        t = (2f0 * (i-1) / (n-1)) - 1f0            # t ∈ [-1, 1]
        Δh = Float32(t) * h_max_deg                # fokban
        sat_scale = 1f0 - desat_mid * (1f0 - abs(t)) # középen kisebb S, széleken 1.0
        out[i] = _hsv_shift_rgba(base, Δh, sat_scale)
    end
    return out
end

const RR_COLORMAP = make_rr_colormap(RGBAf(0, 1, 1, 1); h_max_deg=120f0, desat_mid=0.15f0, n=256)

# RR colormap → 1D textúra (N×1), hogy a v (latitude) mentén mintázható legyen
# Kétpólusú (neg/poz) fix paletta építése – pl. classic vörös/kék
# Lágy, "knee"-es átmenet a közép körül smoothstep-pel (mid_width szabályozza)
@inline function _smoothstep(a::Float32, b::Float32, x::Float32)
    t = clamp((x - a) / (b - a), 0f0, 1f0)
    return t * t * (3f0 - 2f0 * t)
end

function make_bipolar_colormap(pos::RGBAf, neg::RGBAf; n::Int=256,
                               desat_mid::Float32=0.15f0, mid_width::Float32=0.12f0)
    n ≤ 2 && return [neg, pos]
    mw = clamp(mid_width, 1f-4, 1f0)
    out = Vector{RGBAf}(undef, n)
    @inbounds for i in 1:n
        # t ∈ [-1, 1] – negatív pólus → pozitív pólus
        t = Float32((2*(i-1)/(n-1)) - 1)
        # neg→pos keverési arány (0..1) lágy átmenettel a középen (|t|≤mw)
        s = _smoothstep(-mw, mw, t)
        r = (1f0 - s)*neg.r + s*pos.r
        g = (1f0 - s)*neg.g + s*pos.g
        b = (1f0 - s)*neg.b + s*pos.b
        a = (1f0 - s)*alpha(neg) + s*alpha(pos)
        base = RGBAf(Float32(r), Float32(g), Float32(b), Float32(a))
        # közép felé deszaturálás (leginkább t≈0-nál)
        sat_scale = 1f0 - desat_mid * (1f0 - abs(t))
        out[i] = _hsv_shift_rgba(base, 0f0, sat_scale)
    end
    return out
end

# Szélesség‑alapú kék→fehér→vörös gradiens: v=1 (északi pólus) = kék, v=0 (déli) = vörös, v≈0.5 (egyenlítő) = fehér/szürke
@inline function _lerp_rgba(a::RGBAf, b::RGBAf, t::Float32)
    t = clamp(t, 0f0, 1f0)
    return RGBAf(Float32((1-t)*a.r + t*b.r),
                 Float32((1-t)*a.g + t*b.g),
                 Float32((1-t)*a.b + t*b.b),
                 Float32((1-t)*alpha(a) + t*alpha(b)))
end

function make_lat_bwr_colormap(n::Int; blue::RGBAf=RGBAf(0,0,1,1), red::RGBAf=RGBAf(1,0,0,1),
                               mid_luma::Float32=0.92f0, mid_width::Float32=0.12f0)
    n ≤ 2 && return reshape([red, blue], 2, 1)
    mid = RGBAf(mid_luma, mid_luma, mid_luma, 1f0)
    mw  = clamp(mid_width, 1f-4, 0.49f0)  # legfeljebb fél sáv
    out = Vector{RGBAf}(undef, n)
    @inbounds for i in 1:n
        v = Float32((i-1)/(n-1))  # 0..1  (0 = déli, 1 = északi)
        if v < 0.5f0
            # déli félteke: vörös→fehér felé
            t = _smoothstep(0.5f0-mw, 0.5f0, v)
            out[i] = _lerp_rgba(red, mid, t)
        else
            # északi félteke: fehér→kék felé
            t = _smoothstep(0.5f0, 0.5f0+mw, v)
            out[i] = _lerp_rgba(mid, blue, t)
        end
    end
    return reshape(out, n, 1)
end

@inline function rr_texture_for(base_color; h_max_deg=120f0, desat_mid=0.15f0, n=256,
                                 rr_scalar=0f0, beta_max=0.7f0, mid_width=0.12f0,
                                 palette::Symbol=:classic, pos_color=:blue, neg_color=:red,
                                 mid_luma::Float32=0.92f0)
    # ÚJ: klasszikus = szélességi alapú kék→fehér→vörös gradienst ad vissza (északi→déli)
    if palette === :classic
        blue = RGBAf(Makie.to_color(pos_color))  # itt pos_color = :blue az alap
        red  = RGBAf(Makie.to_color(neg_color))  # itt neg_color = :red az alap
        cm   = make_lat_bwr_colormap(n; blue=blue, red=red, mid_luma=mid_luma, mid_width=Float32(mid_width))
        return cm
    else
        # régi RR‑alapú (hue‑shift) fallback
        s = clamp(abs(rr_scalar) / max(beta_max, eps(Float32)), 0f0, 1f0)
        cmap = rr_colormap_for(base_color; h_max_deg=Float32(h_max_deg * s), desat_mid=Float32(desat_mid), n=n)
        if rr_scalar < 0f0
            cmap = reverse(cmap)
        end
        return reshape(cmap, n, 1)
    end
end

# Alapszín → RR colormap helper (instancing‑kompatibilis, későbbi shaderhez is jó)
@inline function rr_colormap_for(base_color; h_max_deg=120f0, desat_mid=0.15f0, n=256)
    base_rgba = RGBAf(Makie.to_color(base_color))
    return make_rr_colormap(base_rgba; h_max_deg=Float32(h_max_deg), desat_mid=Float32(desat_mid), n=n)
end

# -----------------------------------------------------------------------------
# Jelenet (Scene) létrehozása háttérszínnel – mindig LScene, ortografikus kamera
# -----------------------------------------------------------------------------
function setup_scene(; backgroundcolor = RGBf(0.302, 0.322, 0.471))
    fig = Figure(sizeof = (600, 450), backgroundcolor = backgroundcolor, figure_padding = 0)
    scene = LScene(fig[1, 1], show_axis = false)
    cam3d!(scene; projectiontype = :orthographic,
            eyeposition  = Vec3f(0, 0, 1),
            lookat       = Vec3f(0, 0, 0),
            upvector     = Vec3f(0,  1, 0))
    return fig, scene
end

# -----------------------------------------------------------------------------
# RR instancing wrapper – jelenleg pass-through meshscatter!, később shaderrel bővítjük
# -----------------------------------------------------------------------------
struct RRParams
    omega_dir::Vec3f      # forgástengely iránya (unit)
    RR_scalar::Float32    # RR skála (előjeles)
    c_ref::Float32        # referencia-sebesség
    beta_max::Float32     # clamp a stabilitáshoz
    h_max_deg::Float32    # hue-eltolás maximum (°)
    desat_mid::Float32    # közép deszaturálás mértéke [0..1]
end

RRParams(; omega_dir=Vec3f(1,0,0), RR_scalar=0f0, c_ref=1f0,
           beta_max=0.7f0, h_max_deg=120f0, desat_mid=0.15f0) =
    RRParams(omega_dir, RR_scalar, c_ref, beta_max, h_max_deg, desat_mid)

# -----------------------------------------------------------------------------
# Az egyenlítő láthatóságát biztosító tengely választása
#  • V a nézőirány (unit), W az eredeti forgástengely.
#  • A visszaadott tengely A mindig ⟂ V, és lehetőleg W komponensét követi.
# -----------------------------------------------------------------------------
function equator_facing_axis(W::Vec3f, V::Vec3f)
    vhat = V / max(norm(V), eps(Float32))
    what = W / max(norm(W), eps(Float32))
    proj = what - dot(what, vhat) * vhat           # W vetülete a V-re merőleges síkban
    nrm  = norm(proj)
    if nrm < 1f-6
        # W ~ || V: válasszunk stabil, merőleges irányt
        tmp  = abs(dot(what, Vec3f(0,1,0))) < 0.99f0 ? Vec3f(0,1,0) : Vec3f(1,0,0)
        proj = normalize(cross(what, tmp))
    else
        proj /= nrm
    end
    return proj
end

# -----------------------------------------------------------------------------
# Per-vertex RR-színezés – egyszerű félgömb (kamera-független, equator-orientált)
#  • Az oldalt a (A·N) előjele dönti el, ahol A a választott tengely (ált. equator_facing_axis).
#  • Az erősség |RR|/beta_max (γ-görbítve) távolít a középszíntől.
# -----------------------------------------------------------------------------
function rr_vertex_colors(marker_mesh::GeometryBasics.Mesh, rr::RRParams; gamma::Float32=0.8f0,
                          pos_color=:blue, neg_color=:red, axis_override::Union{Nothing,Vec3f}=nothing,
                          force_w::Union{Nothing,Float32}=nothing)
    normals = marker_mesh.normal
    @assert length(normals) > 0 "Marker mesh has no normals"
    A = isnothing(axis_override) ? rr.omega_dir : (axis_override::Vec3f)
    A = A / max(norm(A), eps(Float32))
    # Erősség: |RR| skálázás (gamma görbével) VAGY fix demo érték
    mag = clamp(abs(rr.RR_scalar) / max(rr.beta_max, 1f-6), 0f0, 1f0)
    w0  = mag^gamma  # 0..1
    w   = isnothing(force_w) ? w0 : clamp(force_w::Float32, 0f0, 1f0)
    # Kétpólusú paletta (klasszikus: kék/piros), közép enyhén deszaturálva
    pos = RGBAf(Makie.to_color(pos_color))
    neg = RGBAf(Makie.to_color(neg_color))
    mid = _hsv_shift_rgba(RGBAf((pos.r+neg.r)/2, (pos.g+neg.g)/2, (pos.b+neg.b)/2, 1f0), 0f0, 1f0 - rr.desat_mid)
    cols = Vector{RGBAf}(undef, length(normals))
    @inbounds for i in eachindex(normals)
        N = Vec3f(normals[i])
        # FONTOS: az oldal meghatározása NE függjön az RR előjelétől (különben RR=0 → minden ugyanaz)
        side_sign = sign(dot(A, N))  # +1: „északi”→pos, −1: „déli”→neg
        side_col = side_sign ≥ 0f0 ? pos : neg
        r = (1f0 - w)*mid.r + w*side_col.r
        g = (1f0 - w)*mid.g + w*side_col.g
        b = (1f0 - w)*mid.b + w*side_col.b
        cols[i] = RGBAf(Float32(r), Float32(g), Float32(b), 1f0)
    end
    return cols
end
