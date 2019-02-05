#hoursperyear(yr::Integer) = isleap(yr) ? 8784 : 8760
isleap(yr::Integer) = yr % 4 == 0 && (yr % 100 != 0 || yr % 400 == 0)
flip(x) = permutedims(x, (2,1))

showall(x) = show(stdout, "text/plain", x)

# groupedbar(rand(10,5), bar_position = :stack, lab=["A" "B" "C" "D" "E"])
# groupedbar([1:10;12;12], [rand(10,5) zeros(10,5); zeros(2,10)], bar_position = :stack,
#         lab=["" "" "" "" "" "A" "B" "C" "D" "E"], color=[1 2 3 4 5 5 4 3 2 1], xlim=(0,11))

function groupedbarflip(data; args...)
    newargs = Dict(args)
	nbars, ncolors = size(data)
	x = [1:nbars; nbars+2; nbars+2]
	newdata = [data zeros(nbars,ncolors); zeros(2,ncolors*2)]
    if haskey(newargs, :label)
	   newargs[:label] = [permutedims(repeat([""], ncolors)) reverse(newargs[:label],dims=2)]
    end
    colors = get(newargs, :color, (1:ncolors)')
    newargs[:color] = [colors reverse(colors,dims=2)]
    newargs[:xlim] = (0, nbars+1)
    groupedbar(x, newdata; newargs...)
end

@userplot StackedArea

# a simple "recipe" for Plots.jl to get stacked area plots
# usage: stackedarea(xvector, datamatrix, plotsoptions)
@recipe function f(pc::StackedArea)
    x, y = pc.args
    n = length(x)
    y = cumsum(y, dims=2)
    seriestype := :shape

	# create a filled polygon for each item
    for c=1:size(y,2)
        sx = vcat(x, reverse(x))
        sy = vcat(y[:,c], c==1 ? zeros(n) : reverse(y[:,c-1]))
        @series (sx, sy)
    end
end

@userplot Areaplot
@recipe function f(a::Areaplot)
    data = cumsum(a.args[1], dims=2)
    seriestype := :line
    fillrange := 0
    @series begin
        data[:,1]
    end
    for i in 2:size(data, 2)
    @series begin
            fillrange := data[:,i-1]
            data[:,i]
        end
    end
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