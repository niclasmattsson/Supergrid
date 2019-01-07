#hoursperyear(yr::Integer) = isleap(yr) ? 8784 : 8760
isleap(yr::Integer) = yr % 4 == 0 && (yr % 100 != 0 || yr % 400 == 0)
flip(x) = permutedims(x, (2,1))

showall(x) = show(stdout, "text/plain", x)

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