using GLMakie

import CDFViewer

# ==================================================
#  GLMakie precompilation
# ==================================================

function create_fig()
    screen = GLMakie.Screen(visible=false)
    fig = Figure()
    display(screen, fig)
    ev = fig.scene.events
    return (fig, ev)
end

function get_center(bbox::GLMakie.GeometryBasics.HyperRectangle)::Tuple{Float64, Float64}
    x_center = (bbox.origin[1] + bbox.origin[1] + bbox.widths[1]) / 2
    y_center = (bbox.origin[2] + bbox.origin[2] + bbox.widths[2]) / 2
    return (x_center, y_center)
end

function move_mouse_to_center_of_obj!(ev, obj)
    position = get_center(obj.layoutobservables.computedbbox[])
    ev.mouseposition[] = position
end

function click!(ev)
    ev.mousebutton[] = Makie.MouseButtonEvent(Makie.Mouse.left, Makie.Mouse.press)
    ev.mousebutton[] = Makie.MouseButtonEvent(Makie.Mouse.left, Makie.Mouse.release)
end

function click_at!(ev, obj)
    move_mouse_to_center_of_obj!(ev, obj)
    click!(ev)
end

function interact_with_obj!(fig, ax, obj)
    ev = fig.scene.events
    inspector = DataInspector(fig[1,1])
    Makie.show_data_recursion(inspector, obj, 1)
    sleep(1.0)
    move_mouse_to_center_of_obj!(ev, ax)
    sleep(2.0)
    # zoom
    ev.scroll[] = (0, 5)
    sleep(1.0)
    ev.scroll[] = (0, -2)
    sleep(0.1)
    # move
    ev.mousebutton[] = Makie.MouseButtonEvent(Makie.Mouse.right, Makie.Mouse.press)
    old_pos = ev.mouseposition[]
    ev.mouseposition[] = (old_pos[1] + 30.0, old_pos[2] + 30.0)
    ev.mousebutton[] = Makie.MouseButtonEvent(Makie.Mouse.right, Makie.Mouse.release)
    sleep(1.0)
    # reset view
    move_mouse_to_center_of_obj!(ev, ax)
    ev.keyboardbutton[] = Makie.KeyEvent(Makie.Keyboard.left_control, Makie.Keyboard.press)
    click!(ev)
    ev.keyboardbutton[] = Makie.KeyEvent(Makie.Keyboard.left_control, Makie.Keyboard.release)
    sleep(1.0)
    # zoom / rotate
    ev.mousebutton[] = Makie.MouseButtonEvent(Makie.Mouse.left, Makie.Mouse.press)
    old_pos = ev.mouseposition[]
    ev.mouseposition[] = (old_pos[1] + 30.0, old_pos[2] + 30.0)
    ev.mousebutton[] = Makie.MouseButtonEvent(Makie.Mouse.left, Makie.Mouse.release)
    sleep(1.0)
end


for type in (lines!, scatter!)
    println("Evaluating for type: ", type)
    fig, ev = create_fig()
    ax = Axis(fig[1,1])
    obj = type(ax, 1:1000, rand(1000))
    interact_with_obj!(fig, ax, obj)
end

for type in (heatmap!, contour!, contourf!)
    println("Evaluating for type: ", type)
    fig, ev = create_fig()
    ax = Axis(fig[1,1])
    obj = type(ax, rand(10,10))
    interact_with_obj!(fig, ax, obj)
end

for type in (surface!, wireframe!)
    println("Evaluating for type: ", type)
    fig, ev = create_fig()
    ax = Axis3(fig[1,1])
    obj = type(ax, 1:10, 1:10, rand(10,10))
    interact_with_obj!(fig, ax, obj)
end

for type in (volume!, contour!)
    println("Evaluating for type: ", type)
    fig, ev = create_fig()
    ax = Axis3(fig[1,1])
    obj = type(ax, rand(10,10,10))
    interact_with_obj!(fig, ax, obj)
end


println("Evaluating UI elements")
fig, ev = create_fig()

menu = Menu(fig[1,1], options=["1", "2", "3"])
textbox = Textbox(fig[2,1], width = Relative(1))
slider = Slider(fig[3,1], range = 0:0.1:1, tellwidth = false)
toggle = Toggle(fig[4,1], tellwidth = false)
button = Button(fig[5,1], label = "Press me", width = Relative(1))

sleep(3)
click_at!(ev, menu)
sleep(2.0)
click_at!(ev, menu)
sleep(1.0)
click_at!(ev, textbox)
sleep(1.0)
ev.unicode_input[] = 't'
sleep(1.0)
click_at!(ev, slider)
sleep(1.0)
click_at!(ev, toggle)
sleep(1.0)
click_at!(ev, button)
sleep(1.0)


# ==================================================
#  CDFViewer precompilation
# ==================================================

include(joinpath(pkgdir(CDFViewer), "test", "runtests.jl"))