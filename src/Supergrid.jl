module Supergrid

export runmodel, buildmodel, showresults, makesets, makeparameters

#println("Importing packages...")
using JuMP, CPLEX, Gurobi, Parameters, AxisArrays, Plots, JLD2, Statistics

include("helperfunctions.jl")
include("types.jl")
include("inputdataEurasia21.jl")
# include("inputdataEuroChine14.jl")
# include("inputdataChina6.jl")
# include("inputdataEurope8.jl")
# include("inputdataMENA.jl")
include("jumpmodel.jl")
include("output.jl")

defaultoptions() = Dict(
		:carbontax => 0.0,						# €/ton CO2
		:maxbiocapacity => 0.05,				# share of peak demand
		:nuclearallowed => true,
		:sampleinterval => 3,
		:selectdays => 1,
		:skipdays => 0,
		:solver => :cplex,
		:threads => 3,
		:showsolverlog => true,
		:rampingconstraints => false,
		:rampingcosts => false,
	)

buildmodel(tax, interval; optionlist...) = buildmodel(; carbontax=float(tax), sampleinterval=interval, optionlist...)

function buildmodel(; optionlist...)
	println("\nReading input data...")
	options = merge(defaultoptions(), optionlist)
	hourinfo = HourSampling(options)
	@time sets = makesets(hourinfo)
	@time params = makeparameters(sets, hourinfo)
	println("\nBuilding model...")
	modelname = initjumpmodel(options)
	print("  - variables:   ")
	@time vars = makevariables(modelname, sets)
	print("  - extra bounds:")
	@time setcapacitybounds(sets, params, vars, options)
	print("  - constraints: ")
	@time constraints = makeconstraints(modelname, sets, params, vars, hourinfo, options)
	print("  - objective:   ")
	@time makeobjective(modelname, sets, vars)

	return ModelInfo(modelname, sets, params, vars, constraints, hourinfo)
end

runmodel(tax, interval; optionlist...) = runmodel(; carbontax=float(tax), sampleinterval=interval, optionlist...)

# BASIC USAGE: (carbon tax 50 €/ton CO2, 1-hour time periods, "true" to make some results charts)
# m, annualelec, capac, tcapac, chart = runmodel(50,1);
function runmodel(; optionlist...)		# carbon tax in €/ton CO2
	model = buildmodel(; optionlist...)

	println("\nSolving model...")
	#writeMPS(model, "model3.mps")
	status = solve(model.modelname)

	annualelec, capac, tcapac, chart = showresults(model)

	return model, annualelec, capac, tcapac, chart
end

end #module