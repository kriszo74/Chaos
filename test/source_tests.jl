# Forras puffer- es hullamtalalat-tesztek.
# A build/update/apply_wave_hit! invariansokat validalja.
# Celfokusz: hatarindexek es determinisztikus frissites.

using Test
using Chaos
using Observables
using StaticArrays

function mk_world(; E = 3.0, density = 1.0, max_t = 10.0)
    return Chaos.World(
        E,
        density,
        max_t,
        Observable(0.0),
        Chaos.Source[],
        Chaos.Point3d[],
        Observable(Float64[]),
        Observable(Chaos.SOURCE_UV_T[]),
        nothing,
        1)
end

function mk_source(;
    act_p = SVector(0.0, 0.0, 0.0),
    RV_u = SVector(1.0, 0.0, 0.0),
    RV_mag = 1.0,
    RR = 0.0,
    bas_t = 0.0,
    anch_p = SVector(0.0, 0.0, 0.0))
    return Chaos.Source(
        act_p,
        0,
        RV_u,
        RV_u,
        RV_mag,
        RR,
        bas_t,
        anch_p,
        1:0,
        Chaos.SOURCE_UV_ID)
end

function add_source_for_test!(world; kwargs...)
    src = mk_source(; kwargs...)
    Chaos.build_source!(world, src)
    push!(world.sources, src)
    return src
end

function pick_emt_k(world, emt, rcv)
    emt_radii = @view world.radii_all[][emt.range]
    emt_k = 0
    min_gap2 = typemax(Float64)
    @inbounds for erix in eachindex(emt_radii)
        r_erix = emt_radii[erix]
        r_erix == 0 && break
        p_erix = SVector(world.positions_all[first(emt.range) + erix - 1]...)
        to_rcv2 = sum(abs2, rcv.act_p - p_erix)
        gap2 = r_erix * r_erix - to_rcv2
        if gap2 < 0 || gap2 >= min_gap2
            continue
        end
        emt_k = erix
        min_gap2 = gap2
    end
    return emt_k
end

function mk_edge_case_world()
    world = mk_world(E = 3.0, density = 1.0, max_t = 2.0)
    emt = add_source_for_test!(world)
    rcv = add_source_for_test!(world, anch_p = SVector(10.0, 0.0, 0.0))
    rcv.act_p = SVector(2.0, 0.5, 0.0)

    world.radii_all[] .= 0.0
    emt_radii = @view world.radii_all[][emt.range]
    emt_radii[1] = 0.5
    emt_radii[2] = 1.0
    emt_radii[3] = 1.0
    return world, emt, rcv
end

@testset "build_source! index invariansok" begin
    world = mk_world(density = 2.0, max_t = 3.0)
    src = mk_source(bas_t = 0.25, RV_mag = 2.0)
    Chaos.build_source!(world, src)

    N = Int(ceil((world.max_t - src.bas_t) * world.density)) + 1
    @test length(src.range) == N
    @test first(src.range) == 1
    @test last(src.range) == N
    @test world.next_start_ix == N + 1
    @test length(world.positions_all) == N
    @test length(world.radii_all[]) == N
    @test length(world.uv_all[]) == N
end

@testset "update_radii! aktiv tartomany invarians" begin
    world = mk_world(density = 2.0, max_t = 10.0)
    src = add_source_for_test!(world)

    world.t[] = 1.25
    Chaos.update_radii!(world)
    radii = @view world.radii_all[][src.range]
    K = ceil(Int, round((world.t[] - src.bas_t) * world.density, digits = 12))

    @test src.act_k == K
    for i in 1:K
        @test radii[i] ≈ (world.t[] - src.bas_t - (i - 1) / world.density)
    end
    K < length(radii) && @test all(==(0.0), radii[K+1:end])
end

@testset "apply_wave_hit! perem: emt_k == length(emt.range)" begin
    world, emt, rcv = mk_edge_case_world()
    @test pick_emt_k(world, emt, rcv) == length(emt.range)
    ok = true
    try
        Chaos.apply_wave_hit!(world)
    catch
        ok = false
    end
    @test ok
end

@testset "apply_wave_hit! determinisztikus RV_u frissites" begin
    world1, _, rcv1 = mk_edge_case_world()
    world2, _, rcv2 = mk_edge_case_world()

    Chaos.apply_wave_hit!(world1)
    Chaos.apply_wave_hit!(world2)

    @test rcv1.RV_u ≈ rcv2.RV_u
    @test all(isfinite, rcv1.RV_u)
end
