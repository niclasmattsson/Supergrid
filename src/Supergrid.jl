module Supergrid

export runmodel, buildmodel, readresults, saveresults, showresults, listresults, loadresults, makesets, makeparameters

#println("Importing packages...")
using JuMP, CPLEX, Gurobi, Parameters, AxisArrays, Plots, JLD2, Statistics

include("helperfunctions.jl")
include("types.jl")
include("inputdataEurasia21.jl")
# include("inputdataEurope8.jl")
# include("inputdataEuroChine14.jl")
# include("inputdataChina6.jl")
# include("inputdataMENA.jl")
include("jumpmodel.jl")
include("output.jl")
include("iewruns.jl")

defaultoptions() = Dict(
		:carbontax => 0.0,				# €/ton CO2
		:carboncap => 1.0,				# global cap in kg CO2/kWh elec  (BAU scenario: ~0.5 kgCO2/kWh elec)
		:maxbiocapacity => 0.05,		# share of peak demand
		:nuclearallowed => true,
		:transmissionallowed => :all,	# :none, :islands, :all
		:hours => 1,					# 1,2,3 or 6 hours per period
		:solarwindarea => 1,			# area multiplier for GIS solar & wind potentials
		:selectdays => 1,
		:skipdays => 0,
		:solver => :cplex,
		:threads => 3,
		:showsolverlog => true,
		:rampingconstraints => false,
		:rampingcosts => false,
		:disabletechs => []
	)

function autorunname(options)
	name = ""
	for (key,value) in setdiff(options, defaultoptions())
		name *= "$key=$value, "
	end
	if isempty(name)
		name = "base"
	else
		name = name[1:end-2]
	end
	name
end

function buildmodel(; optionlist...)
	options, hourinfo, sets, params = buildsetsparams(; optionlist...)
	return buildvarsmodel(options, hourinfo, sets, params)
end

function buildsetsparams(; optionlist...)
	println("\nReading input data...")
	options = merge(defaultoptions(), optionlist)
	hourinfo = HourSampling(options)
	@time sets = makesets(hourinfo)
	@time params = makeparameters(sets, options, hourinfo)
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

	return ModelInfo(modelname, sets, params, vars, constraints, hourinfo, options)	
end

# BASIC USAGE: (carbon tax 50 €/ton CO2, 1-hour time periods, "true" to make some results charts)
# m, annualelec, capac, tcapac, chart = runmodel(50,1);
function runmodel(; name="", group="", optionlist...)		# carbon tax in €/ton CO2
	model = buildmodel(; optionlist...)

	println("\nSolving model...")
	#writeMPS(model, "model3.mps")

	status = solve(model.modelname)
	println("\nSolve status: $status")

	println("\nReading results...")
	results = readresults(model, status)
	if isempty(name)
		name = autorunname(model.options)
	end
	println("\nSaving results to disk...")
	saveresults(results, name, group=group)

	if status == :Optimal
		annualelec, capac, tcapac, chart = showresults(results)
	else
		annualelec, capac, tcapac, chart = nothing, nothing, nothing, nothing
	end

	return results, annualelec, capac, tcapac, chart
end

end #module