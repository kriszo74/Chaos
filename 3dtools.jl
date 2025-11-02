# Gömbfelület generálása (lat–long rács, előallokálva)
function create_detailed_sphere_fast(center::Point3f, r::Float32, res::Int=48)
    @assert res ≥ 8 "res should be ≥ 8 for smooth markers"
    nlats = res
    nlons = 2*res
    W     = nlons + 1
    Nv    = (nlats + 1) * W
    Nt    = 2 * nlats * nlons

    verts  = Vector{Point3f}(undef, Nv)
    uvs    = Vector{Vec2f}(undef, Nv)
    faces  = Vector{GLTriangleFace}(undef, Nt)

    φ = collect(range(0f0, stop=Float32(pi),     length=nlats+1))
    θ = collect(range(0f0, stop=2f0*Float32(pi), length=nlons+1))

    sφ = similar(φ); cφ = similar(φ)
    sθ = similar(θ); cθ = similar(θ)

    @inbounds @simd for i in eachindex(φ)
        sφ[i], cφ[i] = sincos(φ[i])
    end
    @inbounds @simd for j in eachindex(θ)
        sθ[j], cθ[j] = sincos(θ[j])
    end

    @inbounds for i in 0:nlats
        z = cφ[i+1]; s = sφ[i+1]
        v = Float32(1 - i/nlats)
        rowoff = i * W
        @simd for j in 0:nlons
            x = s * cθ[j+1]; y = s * sθ[j+1]
            u = Float32(j/nlons)
            idx = rowoff + j + 1
            verts[idx] = Point3f(center .+ r .* Vec3f(x, y, z))
            uvs[idx]   = Vec2f(v, u)
        end
    end

    k = 0
    @inbounds for i in 1:nlats, j in 1:nlons
        a = (i-1)*W + j
        b = a + 1
        c = a + W
        d = c + 1
        k += 1; faces[k] = GLTriangleFace(a, c, b)
        k += 1; faces[k] = GLTriangleFace(b, c, d)
    end

    normals = Vector{Vec3f}(undef, Nv)
    @inbounds @simd for idx in 1:Nv
        v = Vec3f(verts[idx]) - Vec3f(center)
        normals[idx] = v / r
    end

    return GeometryBasics.Mesh((position = verts, normal = normals, uv = uvs), faces)
end

# Jelenet (Scene) létrehozása – ortografikus kamera
function setup_scene(; backgroundcolor = RGBf(0.302, 0.322, 0.471))
    GLMakie.activate!(; focus_on_show=true, title="Chaos")
    fig = Figure(sizeof = (600, 450), backgroundcolor = backgroundcolor, figure_padding = 0)
    scene = LScene(fig[1, 1], show_axis = false)
    cam3d!(scene; projectiontype = :orthographic,
            eyeposition  = Vec3f(0, 0, 1),
            lookat       = Vec3f(0, 0, 0),
            upvector     = Vec3f(0,  1, 0))
    return fig, scene
end

# 30°-os hue → név hozzárendelés (0,30,…,330)
const HUE30_NAMES = Dict{Int,Symbol}(0=>:red, 30=>:orange, 60=>:yellow, 90=>:chartreuse, 120=>:green, 150=>:springgreen, 180=>:cyan, 210=>:dodgerblue, 240=>:blue, 270=>:indigo, 300=>:magenta, 330=>:deeppink)

# Atlasz 12 közép-hue-hoz; oszlopok r∈[0,1] (parts+1), sorok: neg/mid/pos.
function rr_texture_from_hue(RR_MAX::Float32, RR_STEP::Float32; s::Float32=1f0, v::Float32=1f0) 
    ncols = Int(floor(RR_MAX / RR_STEP)) + 1
    rvals = collect(LinRange(0f0, 1f0, ncols))  # r lépcsők 0..1 között, egyenletes rács (N = parts+1)
    hs    = Float32.(0:30:330)               # 12 közép-hue (fok): 0°,30°,…,330°
    atlas = Matrix{RGBAf}(undef, 3, ncols * 12)  # 3B: inline length(hs)

    @inbounds for (i, hmid) in enumerate(hs)
        Δ::Float32 = (mod(hmid, 60f0) == 0f0) ? 60f0 : 30f0  # Δ (fok): 60°, ha h_mid % 60 == 0; különben 30°
        base = (i-1) * ncols  # atlasz-blokk oszlop offsetje az i. közép-hue-hoz (0-indexelt blokkok)
        for j in 1:ncols
            r = rvals[j]  # normált forgási skála: r ∈ [0,1] (0: nincs eltérés, 1: max. Δ)
            δ = r * Δ  # hue-eltérés (fok) a közép-hue-hoz képest: δ ∈ [0, Δ]
            hneg = hmid - δ  # kék irány (negatív eltérítés) – 'neg' sáv
            hpos = hmid + δ  # vörös irány (pozitív eltérítés) – 'pos' sáv
            col = base + j  # atlasz oszlopindex: adott hue-blokk kezdete + lokális oszlop
            atlas[1, col] = RGBAf(HSV(mod(hneg, 360f0), s, v))  # sor1: neg (kékelt) – HSV→RGBAf, 360°-ra modolva
            atlas[2, col] = RGBAf(HSV(hmid, s, v))              # sor2: mid (alapszín) – változatlan hue
            atlas[3, col] = RGBAf(HSV(mod(hpos, 360f0), s, v))  # sor3: pos (vöröselt) – HSV→RGBAf, 360°-ra modolva
        end
    end
    return atlas, ncols, ncols * 12  # pl. parts=20 → 3 × ((20+1)*12) = 3 × 252
end