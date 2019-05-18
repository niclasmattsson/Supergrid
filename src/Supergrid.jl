module Supergrid

export runmodel, buildmodel, readresults, saveresults, analyzeresults, listresults, loadresults, makesets, makeparameters,
        fix_timezone_error

#println("Importing packages...")
using JuMP, CPLEX, Gurobi, Parameters, AxisArrays, Plots, JLD2, Statistics

include("helperfunctions.jl")
include("types.jl")
include("inputdata.jl")
include("jumpmodel.jl")
include("output.jl")
include("iewruns.jl")

defaultoptions() = Dict(
        :regionset => :europe8,             # :eurasia21, :europe8
        :carbontax => 0.0,                  # €/ton CO2
        :carboncap => 1.0,                  # global cap in kg CO2/kWh elec  (BAU scenario: ~0.5 kgCO2/kWh elec)
        :maxbioenergy => 0.05,              # max share of biofuel of annual regional electricity demand (assuming CCGT, less if GT) 
        :nuclearallowed => true,
        :globalnuclearlimit => Inf,         # maximum total nuclear capacity in all regions (GW)
        :hydroinvestmentsallowed => false,
        :transmissionallowed => :all,       # :none, :islands, :all
        :hours => 1,                        # 1,2,3 or 6 hours per period
        :solarwindarea => 1,                # area multiplier for GIS solar & wind potentials
        :selectdays => 1,
        :skipdays => 0,
        :solver => :cplex,
        :threads => 3,
        :showsolverlog => true,
        :rampingconstraints => false,
        :rampingcosts => false,
        :disabletechs => [],
        :disableregions => [],
        :islandindexes => [],               # [1:8, 9:15, 16:21] for eurasia21
        :resultsfile => "results.jld2"      # use "" to skip saving the results in the database
    )

function autorunname(options)
    name = ""
    for (key,value) in setdiff(options, defaultoptions())
        name *= "$key=$value, "
    end
    if isempty(name)
        name = "default"
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
    if options[:regionset] == :eurasia21 && isempty(options[:islandindexes])
        options[:islandindexes] = [1:8, 9:15, 16:21]    # change defaults for eurasia21
    end
    hourinfo = HourSampling(options)
    @time sets = makesets(hourinfo, options)
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

# BASIC USAGE: (carbon tax 50 €/ton CO2, 3-hour time periods)
# m, annualelec, capac, tcapac, chart = runmodel(carboncap=50, hours=3, [more options]...);
function runmodel(; name="", group="", optionlist...)       # carbon tax in €/ton CO2
    model = buildmodel(; optionlist...)

    println("\nSolving model...")
    #writeMPS(model, "model3.mps")

    status = solve(model.modelname)
    println("\nSolve status: $status")

    println("\nReading results...")
    results = readresults(model, status)

    filename = model.options[:resultsfile]

    if !isempty(filename)
        if isempty(name)
            name = autorunname(model.options)
        end
        println("\nSaving results to disk...")
        saveresults(results, name, resultsfile=filename, group=group)
    end

    annualelec, capac, tcapac, chart = analyzeresults(results)

    if status != :Optimal
        @warn "The solver did not report an optimal solution. It could still be fine, but examine the log."
    end

    return results, annualelec, capac, tcapac, chart
end

end #module