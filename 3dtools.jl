# ---- 3dtools.jl ----

# Színkezeléshez használjuk a Colors csomagot (Makie függősége)
using Colors
using Makie, GLMakie
using GeometryBasics: Point3f, GLTriangleFace, Sphere
# Gömbfelület generálása egyetlen hívással (GeometryBasics helper)
# center  – a gömb közepe
# radius  – sugár
# res     – θ és φ irányú felbontás (≥ 3)
function create_detailed_sphere(center::Point3f, r::Float32, res::Int=48)
    @assert res ≥ 8 "res should be ≥ 8 for smooth markers"
    # Hosszúsági–szélességi rács UV-val és normállal (instancing‑kompatibilis markerhez)
    nlats = res
    nlons = 2res
    verts  = Point3f[]
    uvs    = Vec2f[]
    faces  = GLTriangleFace[]
    for i in 0:nlats
        φ = π * (i/nlats)              # 0..π
        z = cos(φ); s = sin(φ)
        for j in 0:nlons
            θ = 2π * (j/nlons)         # 0..2π
            x = s*cos(θ); y = s*sin(θ)
            p = center + r * Vec3f(x, y, z)
            push!(verts, Point3f(p))
            # UV: u∈[0,1], v∈[0,1] (v=1 a „északi” pólus felé)
            u = Float32(j/nlons)
            v = Float32(1 - i/nlats)
            push!(uvs, Vec2f(u, v))
        end
    end
    # Háromszögarcok
    W = nlons + 1
    for i in 1:nlats, j in 1:nlons
        a = (i-1)*W + j
        b = a + 1
        c = a + W
        d = c + 1
        push!(faces, GLTriangleFace(a, c, b))
        push!(faces, GLTriangleFace(b, c, d))
    end
    # Normálok: sugárirány
    normals = Vec3f[((Vec3f(v) - Vec3f(center)) / r) for v in verts]
    return GeometryBasics.Mesh((position = verts, normal = normals, uv = uvs), faces)
end

# ÚJ: lat–long alapú unit-gömb geometriája (verts, faces, normals)
function build_unit_sphere(res::Int=48)
    sp    = Sphere(Point3f(0,0,0), 1f0)
    verts = GeometryBasics.coordinates(sp, res)           # Vector{Point3f}
    faces = GeometryBasics.faces(sp, res)                 # Faces (triangles)
    # unit gömbnél a normál a középpontból kifelé mutat
    norms = map(verts) do v
        n = Vec3f(v)
        invlen = 1f0 / sqrt(n[1]^2 + n[2]^2 + n[3]^2)
        Vec3f(n[1]*invlen, n[2]*invlen, n[3]*invlen)
    end
    return (verts, faces, norms)
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
function make_bipolar_colormap(pos::RGBAf, neg::RGBAf; n::Int=256, desat_mid::Float32=0.15f0)
    n ≤ 2 && return [neg, pos]
    mid = RGBAf(
        Float32((pos.r + neg.r)/2),
        Float32((pos.g + neg.g)/2),
        Float32((pos.b + neg.b)/2),
        Float32((alpha(pos) + alpha(neg))/2)
    )
    # közép enyhe deszaturálása HSV-ben
    mid = _hsv_shift_rgba(mid, 0f0, 1f0 - desat_mid)
    left  = range(neg, stop=mid, length=div(n,2))
    right = range(mid, stop=pos, length=n - length(left))
    return [left...; right...]
end

@inline function rr_texture_for(base_color; h_max_deg=120f0, desat_mid=0.15f0, n=256, rr_scalar=0f0, beta_max=0.7f0,
                                 palette::Symbol=:classic, pos_color=:blue, neg_color=:red)
    # RR arány szerinti skála: |RR|/beta_max ∈ [0,1]
    s = clamp(abs(rr_scalar) / max(beta_max, eps(Float32)), 0f0, 1f0)
    cmap = if palette === :classic
        make_bipolar_colormap(RGBAf(Makie.to_color(pos_color)), RGBAf(Makie.to_color(neg_color)); n=n, desat_mid=Float32(desat_mid))
    else
        rr_colormap_for(base_color; h_max_deg=Float32(h_max_deg * s), desat_mid=Float32(desat_mid), n=n)
    end
    # Előjel: RR<0 esetén a két pólus felcserélése (kolormap megfordítása)
    if rr_scalar < 0f0
        cmap = reverse(cmap)
    end
    return reshape(cmap, n, 1)  # Matrix{RGBAf} (N×1)
end

# Alapszín → RR colormap helper (instancing‑kompatibilis, későbbi shaderhez is jó)
@inline function rr_colormap_for(base_color; h_max_deg=120f0, desat_mid=0.15f0, n=256)
    base_rgba = RGBAf(Makie.to_color(base_color))
    return make_rr_colormap(base_rgba; h_max_deg=Float32(h_max_deg), desat_mid=Float32(desat_mid), n=n)
end

# -----------------------------------------------------------------------------
# Jelenet (Scene) létrehozása háttérszínnel – mindig LScene, ortografikus kamera
# -----------------------------------------------------------------------------
function setup_scene(; backgroundcolor = RGBf(1.0, 1.0, 1.0)) #backgroundcolor = RGBf(0.302, 0.322, 0.471)
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

"""
rr_spheres!(scene; positions, radii, base_color=:cyan, alpha=0.2, rr=RRParams(), res=48)

Instancing-barát wrapper a jelenlegi meshscatter! fölé. Jelen állapotban csak
átadja a hívást (egyszínű), de a későbbiekben shaderrel Doppler-félgömbös
színezést valósítunk meg *változatlan* hívói API mellett.
"""
# --- Overload: rr_spheres! fogadjon Observable radii-t is ---
function rr_spheres!(scene; positions, radii, base_color=:cyan, alpha=0.2, rr::RRParams=RRParams(), res::Int=48,
                        
                        use_rr_texture::Bool=true, use_rr_shader::Bool=false, rr_palette::Symbol=:classic)  # IDEIGLENES textúra; shader hamarosan átveszi
    @assert res ≥ 8 "res should be ≥ 8 for smooth markers"
    local ph = meshscatter!(scene, positions;
        marker       = create_detailed_sphere(Point3f(0, 0, 0), 1f0, res),
        markersize   = radii,          # Vector vagy Observable is lehet
        color        = base_color,     # ideiglenes, azonnal felülírjuk textúrával
        transparency = true,
        alpha        = alpha)
    # (Opcionális) Orientáció: a marker helyi z‑t az RR‑tengelyhez igazítjuk
    try
        # Megjegyzés: a rotation típus backendenként eltérő (pl. Quaternion / Euler / vektor)
        ph[:rotation][] = rr.omega_dir
    catch
    end
    # RR‑textúra a v (latitude) mentén – a shader a mesh UV‑t fogja mintázni
    if use_rr_texture  # IDEIGLENES: shader nélkül a colormap-ot textúraként kötjük a mesh UV-hoz
        try
            ph[:color][] = rr_texture_for(base_color; h_max_deg=rr.h_max_deg, desat_mid=rr.desat_mid, n=256,
                                          rr_scalar=rr.RR_scalar, beta_max=rr.beta_max,
                                          palette=rr_palette)
            try
                ph[:interpolate][] = true
            catch
            end
        catch
        end
    end
        # Shaderes út bekapcsolása (még kísérleti – biztonságos fallback a textúra)
    if use_rr_shader
        try
            enable_rr_shader!(ph; base_color, rr)
            # ha shader megy, a textúra-réteget kikapcsolhatjuk (majd a shader számol mindent)
        catch err
            @warn "enable_rr_shader! failed – fallback to texture" err
        end
    end
    return ph
end

# -----------------------------------------------------------------------------
# KÍSÉRLETI: RR shader felvezetése – uniformok + fragment kiegészítés
# Megjegyzés: GLMakie v0.13.x alatt a modify_shader! API elérhető, de backend-függő.
# Itt egy biztonságos váz: ha bárhol hibázik, csendben visszaadjuk a textúrás utat.
# -----------------------------------------------------------------------------
function enable_rr_shader!(ph; base_color=:cyan, rr::RRParams=RRParams())
    # Uniformok felkötése a plotra (Makie attrként)
    try
        ph[:rr_omega_dir][] = rr.omega_dir
        ph[:rr_scalar][]    = rr.RR_scalar
        ph[:rr_beta_max][]  = rr.beta_max
        ph[:rr_c_ref][]     = rr.c_ref
        ph[:rr_hmax][]      = rr.h_max_deg * (π/180f0)
        ph[:rr_desat][]     = rr.desat_mid
        ph[:rr_base_rgb][]  = Vec3f(RGB(to_color(base_color))...)  # alap RGB (0..1)
    catch
        # ha az attribútumok nem támogatottak, lépjünk vissza
        return false
    end

    # Shader módosítás – csak GLMakie alatt értelmezett
    try
        GLMakie.modify_shader!(ph, fragment = rr_fragment_shader())
    catch
        return false
    end
    return true
end

# Fragment-shader váz: β számítás (tangenciális komponens) + hue‑eltolás előkészítés.
# Jelenleg csak felvezetés; a végső színt még a Makie pipeline adja vissza.
function rr_fragment_shader()
    return raw"""
        vec3 rr_apply_hsv(vec3 rgb, float dh, float desat){
            // nagyon egyszerű HSV konverzió a shaderben (helyi, közelítő)
            float cmax = max(max(rgb.r, rgb.g), rgb.b);
            float cmin = min(min(rgb.r, rgb.g), rgb.b);
            float delta = cmax - cmin;
            float h = 0.0;
            if (delta > 1e-6){
                if (cmax == rgb.r)      h = mod((rgb.g - rgb.b)/delta, 6.0);
                else if (cmax == rgb.g) h = (rgb.b - rgb.r)/delta + 2.0;
                else                    h = (rgb.r - rgb.g)/delta + 4.0;
                h /= 6.0;
            }
            float s = (cmax <= 1e-6) ? 0.0 : (delta / cmax);
            float v = cmax;
            // hue eltolás radián helyett [0,1] körön
            h = fract(h + dh/(2.0*3.14159265));
            s = clamp(s * (1.0 - desat), 0.0, 1.0);
            // vissza RGB-be (HSV → RGB)
            float c = v * s;
            float x = c * (1.0 - abs(mod(h*6.0, 2.0) - 1.0));
            float m = v - c;
            vec3 rp;
            if (0.0 <= h && h < 1.0/6.0)      rp = vec3(c, x, 0);
            else if (1.0/6.0 <= h && h < 2.0/6.0) rp = vec3(x, c, 0);
            else if (2.0/6.0 <= h && h < 3.0/6.0) rp = vec3(0, c, x);
            else if (3.0/6.0 <= h && h < 4.0/6.0) rp = vec3(0, x, c);
            else if (4.0/6.0 <= h && h < 5.0/6.0) rp = vec3(x, 0, c);
            else                                  rp = vec3(c, 0, x);
            return rp + vec3(m);
        }

        void rr_fragment_main(inout vec4 color){
            // inputok: normál (N), nézőirány (V), omega_dir (W)
            vec3 N = normalize(@normal);
            vec3 W = normalize(@rr_omega_dir);
            // ortografikus kamera: V ~ (0,0,-1)
            vec3 V = vec3(0.0, 0.0, -1.0);
            // tangenciális irány és LOS komponens
            vec3 vt = normalize(cross(W, N));
            float beta = dot(vt, V) * @rr_scalar / max(@rr_c_ref, 1e-6);
            beta = clamp(beta, -@rr_beta_max, @rr_beta_max);
            // hue eltolás mértéke
            float dh = beta * @rr_hmax;   // radiánban
            float des = @rr_desat * (1.0 - abs(beta)/@rr_beta_max);
            vec3 base = @rr_base_rgb;
            vec3 col  = rr_apply_hsv(base, dh, des);
            color.rgb = col;
        }
    """
end
