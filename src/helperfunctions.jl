#hoursperyear(yr::Integer) = isleap(yr) ? 8784 : 8760
isleap(yr::Integer) = yr % 4 == 0 && (yr % 100 != 0 || yr % 400 == 0)
flip(x) = permutedims(x, (2,1))

showall(x) = show(stdout, "text/plain", x)

@userplot StackedArea
# Bugfix of StatsPlots.areaplot(), i.e. reverse the legend order. 
@recipe function f(a::StackedArea)
    data = cumsum(a.args[end], dims=2)
    n = size(data, 2)
    x = length(a.args) == 1 ? (1:size(data, 1)) : a.args[1]
    seriestype := :line
    labels = haskey(plotattributes, :label) ? plotattributes[:label] : ["y$i" for i = 1:n]

    for i in n:-1:1
        @series begin
            fillrange := i > 1 ? data[:,i-1] : 0
            fillcolor --> i
            label := labels[i]
            x, data[:,i]
        end
    end
end

@userplot StackedArea_Polygons
# A simple "recipe" for Plots.jl to get stacked area plots. This version draws a line around each color patch.
# (Calling the other function with linecolor=:black doesn't draw the color around the sides or bottom.)
# usage: stackedarea(xvector, datamatrix, plotsoptions)
@recipe function f(a::StackedArea_Polygons)
    data = cumsum(a.args[end], dims=2)
    nx, nseries = size(data)
    x = length(a.args) == 1 ? (1:nx) : a.args[1]
    labels = haskey(plotattributes, :label) ? plotattributes[:label] : ["y$i" for i = 1:n]
    seriestype := :shape

    # create a filled polygon for each item
    for i = nseries:-1:1
        sx = vcat(x, reverse(x))
        sy = vcat(data[:, i], i==1 ? zeros(nx) : reverse(data[:, i-1]))
        @series begin
            fillcolor --> i
            label := labels[i]
            (sx, sy)
        end
    end
end

@userplot StackedBar
# Bugfix of StatsPlots.groupedbar(), i.e. reverse the legend order. Also default to bar_position=:stack.
@recipe function f(g::StackedBar; spacing = 0)
    x, y = StatsPlots.grouped_xy(g.args...)

    nr, nc = size(y)

    isstack = pop!(plotattributes, :bar_position, :stack) == :stack

    # extract xnums and set default bar width.
    # might need to set xticks as well
    xnums = if eltype(x) <: Number
        xdiff = length(x) > 1 ? mean(diff(x)) : 1
        bar_width --> 0.8 * xdiff
        x
    else
        bar_width --> 0.8
        ux = unique(x)
        xnums = (1:length(ux)) .- 0.5
        xticks --> (xnums, ux)
        xnums
    end
    @assert length(xnums) == nr

    # compute the x centers.  for dodge, make a matrix for each column
    x = if isstack
        x
    else
        bws = plotattributes[:bar_width] / nc
        bar_width := bws * clamp(1 - spacing, 0, 1)
        xmat = zeros(nr,nc)
        for r=1:nr
            bw = StatsPlots._cycle(bws, r)
            farleft = xnums[r] - 0.5 * (bw * nc)
            for c=1:nc
                xmat[r,c] = farleft + 0.5bw + (c-1)*bw
            end
        end
        xmat
    end

    # compute fillrange
    fillrange := if isstack
        y, fr = StatsPlots.groupedbar_fillrange(reverse(y, dims=2))
        fr
    else
        get(plotattributes, :fillrange, nothing)
    end

    seriestype := :bar

    if isstack
        label := haskey(plotattributes, :label) ? reverse(plotattributes[:label],dims=2) : ["y$i" for j = 1:1, i = nc:-1:1]
        fillcolor --> permutedims(nc:-1:1)
    end

    x, y
end

#=
function printtable(title::String, setnames::Vector, datarows::Array, columnname::Symbol = :none)
    println(title)
    push!(setnames, :value)
    df = DataFrame([fill(Symbol, length(setnames)-1); Float64], setnames, 0)
    for row in datarows
        push!(df, row)
    end
    if columnname != :none
        df = unstack(df, columnname, :value)
    end
    show(IOContext(STDOUT, displaysize=(100,120)), "text/plain", df)        
end

printtable(jarr::JuMP.JuMPArray{Float64,2}) = printtable("", jarr)
printtable(title::String, jarr::JuMP.JuMPArray{Float64,2}) =
    println("$title\n", DataFrame([jarr.indexsets[1] jarr.innerArray], [:_; jarr.indexsets[2]]))
=#
