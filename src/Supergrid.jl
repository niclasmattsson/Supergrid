module Supergrid

export runmodel, buildmodel, readresults, saveresults, analyzeresults, listresults, loadresults, makesets, makeparameters,
        fix_timezone_error, chart_energymix_scenarios

using JuMP, CPLEX, Gurobi, GLPKMathProgInterface, GLPK, Clp, Parameters, AxisArrays, Plots, JLD2, Statistics

include("helperfunctions.jl")
include("types.jl")
include("inputdata.jl")
include("jumpmodel.jl")
include("output.jl")
include("iewruns.jl")

function defaultoptions()
    defaults = Dict(
        :regionset => :Eurasia21,           # :eurasia21, :europe8
        :inputdatasuffix => "",             # e.g. "_landx2" to read solar input data "GISdata_solar2018_Europe8_landx2.mat" 
        :islandindexes => [],               # superregion groupings, defaults to [1:8, 9:15, 16:21] for eurasia21, [] for europe8
        :carbontax => 0.0,                  # €/ton CO2
        :carboncap => 1.0,                  # global cap in kg CO2/kWh elec  (BAU scenario: ~0.5 kgCO2/kWh elec)
        :discountrate => 0.05,
        :maxbioenergy => 0.05,              # max share of biofuel of annual regional electricity demand (assuming CCGT, less if GT) 
        :nuclearallowed => true,
        :globalnuclearlimit => Inf,         # maximum total nuclear capacity in all regions (GW)
        :hydroinvestmentsallowed => false,
        :transmissionallowed => :all,       # :none, :islands, :all
        :hours => 1,                        # 1,2,3 or 6 hours per period
        :solarwindarea => 1,                # area multiplier for GIS solar & wind potentials
        :datayear => 2018,                  # year of the ERA5 input data (produced by GlobalEnergyGIS.jl)
        :selectdays => 1,
        :skipdays => 0,
        :solver => :cplex,
        :threads => 3,
        :showsolverlog => true,
        :rampingconstraints => false,
        :rampingcosts => false,
        :disabletechs => [],
        :disableregions => [],
        :resultsfile => "results.jld2"      # use "" to skip saving the results in the database
    )
    if defaults[:regionset] == :eurasia21 && isempty(defaults[:islandindexes])
        defaults[:islandindexes] = [1:8, 9:15, 16:21]    # change defaults for eurasia21
    end
    return defaults
end

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

    #writeMPS(model, "model3.mps")
    if model.options[:solver] == :cplex
        println("\nSolving model using CPLEX version $(CPLEX.version())...")
    else
        println("\nSolving model...")
    end

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