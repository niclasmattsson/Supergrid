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
include("iewruns.jl")

defaultoptions() = Dict(
		:carbontax => 0.0,				# €/ton CO2
		:carboncap => 1.0,				# global cap in kg CO2/kWh elec  (BAU scenario: ~0.5 kgCO2/kWh elec)
		:maxbiocapacity => 0.05,		# share of peak demand
		:nuclearallowed => true,
		:transmissionallowed => :all,			# :none, :islands, :all
		:sampleinterval => 3,
		:selectdays => 1,
		:skipdays => 0,
		:solver => :cplex,
		:threads => 2,
		:showsolverlog => true,
		:rampingconstraints => false,
		:rampingcosts => false,
		:disabletechs => []
	)

buildmodel(tax, interval; optionlist...) = buildmodel(; carbontax=float(tax), sampleinterval=interval, optionlist...)

function buildmodel(; optionlist...)
	options, hourinfo, sets, params = buildsetsparams(; optionlist...)
	return buildvarsmodel(options, hourinfo, sets, params)
end

function buildsetsparams(; optionlist...)
	println("\nReading input data...")
	options = merge(defaultoptions(), optionlist)
	hourinfo = HourSampling(options)
	@time sets = makesets(hourinfo)
	@time params = makeparameters(sets, hourinfo)
	return options, hourinfo, sets, params
end

function buildvarsmodel(options, hourinfo, sets, params)
	println("\nBuilding model...")
	modelname = initjumpmodel(options)
	print("  - variables:   ")
	@time vars = makevariables(modelname, sets)
	print("  - extra bounds:")
	@time setbounds(sets, params, vars, options)
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
	println("\nSolve status: $status")

	if status == :Optimal
		annualelec, capac, tcapac, chart = showresults(model)
	else
		annualelec, capac, tcapac, chart = nothing, nothing, nothing, nothing
	end

	return model, annualelec, capac, tcapac, chart
end

end #module