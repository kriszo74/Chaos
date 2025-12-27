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

# egységvektor és hossz kiszámítása
function unit_and_mag(v::SVector{3,Float64})
    v === SVector(0.0,0.0,0.0) && return (nothing, nothing)
    mag = sqrt(sum(abs2, v))
    return (v / mag, mag)
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
function rr_texture_from_hue(RR_MAX::Float32, RR_STEP::Float32; s::Float32=1f0, v::Float32=1f0, alphas::Vector{Float32}=Float32[1f0]) 
    ncols = Int(floor(RR_MAX / RR_STEP)) + 1                       # RR oszlopszám (RR_MAX/RR_STEP + 1)
    rvals = collect(LinRange(0f0, 1f0, ncols))                     # RR lépcsők 0..1 normálva
    hs    = Float32.(0:30:330)                                     # 12 közép-hue 0..330 fok
    alpha_count = length(alphas)                                   # alpha lépések száma
    atlas = Matrix{RGBAf}(undef, 3, ncols * alpha_count * 12)      # atlasz: 3 sor, 12 blokk, RR×alpha oszlop

    @inbounds for (i, hmid) in enumerate(hs)
        Δ::Float32 = (mod(hmid, 60f0) == 0f0) ? 60f0 : 30f0        # Δ: 60°, ha h_mid % 60 == 0, különben 30°
        base = (i-1) * ncols * alpha_count                         # hue-blokk oszlop offset
        for j in 1:ncols
            r = rvals[j]                                           # normált forgási skála r ∈ [0,1]
            δ = r * Δ                                              # hue-eltérés a közép-hue-hoz képest
            hneg = hmid - δ                                        # negatív eltérítés hue
            hpos = hmid + δ                                        # pozitív eltérítés hue
            for k in 1:alpha_count
                col = base + (j-1) * alpha_count + k               # oszlopindex hue/RR/alpha szerint
                atlas[1, col] = RGBAf(HSV(mod(hneg, 360f0), s, v), alphas[k])  # neg sáv
                atlas[2, col] = RGBAf(HSV(hmid, s, v), alphas[k])              # mid sáv
                atlas[3, col] = RGBAf(HSV(mod(hpos, 360f0), s, v), alphas[k])  # pos sáv
            end
        end
    end
    return atlas, ncols * alpha_count, ncols * alpha_count * 12   # RR×alpha oszlop, hue blokk *12
end
