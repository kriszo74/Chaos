function setup_scene(; backgroundcolor = RGBf(0.302, 0.322, 0.471), use_axis3 = true)
    # Create the figure with the specified background color
    fig = Figure(backgroundcolor = backgroundcolor)
    
    # Create the scene based on the use_axis3 parameter
    if use_axis3
        scene = Axis3(fig[1, 1],
            aspect = :data,
            perspectiveness = 0.0,
            elevation = π/2,
            azimuth = 3π/2,
            xgridvisible = false,
            ygridvisible = false,
            zgridvisible = false,
            xspinesvisible = false,
            xlabelvisible = false,
            xticksvisible = false,
            xticklabelsvisible = false,
            yspinesvisible = false,
            ylabelvisible = false,
            yticksvisible = false,
            yticklabelsvisible = false,
            zspinesvisible = false,
            zlabelvisible = false,
            zticksvisible = false,
            zticklabelsvisible = false
        )
    else
        scene = LScene(fig[1, 1], show_axis = false)
        cam3d!(scene, projectiontype = :orthographic, eyeposition = Vec3f(0,0,4), lookat = Vec3f(0, 0, 0), upvector = Vec3f(0, 1, 0))
    end
    
    # Return both the figure and the scene
    return fig, scene
end