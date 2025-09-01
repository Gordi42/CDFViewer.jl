using GLMakie
using Test

a = Dict(i => Observable(i) for i in 1:3)

b = Observable(Dict(i => x[] for (i, x) in a))

for (k, v) in a
    on(v) do _
        b[][k] = v[]
        notify(b)
    end
end

counter = Observable(0)
on(b) do v
    counter[] += 1
    println("b changed to $v")
end

@test b[][1] == 1
a[1][] = 8
@test b[][1] == 8

@test counter[] == 1