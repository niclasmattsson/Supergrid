function builddispatchmodel(capacity, transmissioncapacity; optionlist...)
    options, hourinfo, sets, params = buildsetsparams(; optionlist...)
    return builddispatchvarsmodel(capacity, transmissioncapacity, options, hourinfo, sets, params)
end

function builddispatchvarsmodel(capacity, transmissioncapacity, options, hourinfo, sets, params)
    println("\nBuilding model...")
    modelname = initjumpmodel(options)
    print("  - variables:   ")
    @time vars = makedispatchvariables(modelname, sets)
    print("  - extra bounds:")
    @time setdispatchbounds(capacity, transmissioncapacity, sets, params, vars, hourinfo, options)
    print("  - constraints: ")
    @time constraints = makedispatchconstraints(capacity, transmissioncapacity, modelname, sets, params, vars, hourinfo, options)
    print("  - objective:   ")
    @time makeobjective(modelname, sets, vars)

    return ModelInfo(modelname, sets, params, vars, constraints, hourinfo, options) 
end

# BASIC USAGE: (carbon tax 50 €/ton CO2, 3-hour time periods)
# m, annualelec, capac, tcapac, chart = runmodel(carboncap=50, hours=3, [more options]...);
function rundispatchmodel(capacity, transmissioncapacity; name="", group="", optionlist...)       # carbon tax in €/ton CO2
    model = builddispatchmodel(capacity, transmissioncapacity; optionlist...)

    #writeMPS(model, "model3.mps")
    if model.options[:solver] == :cplex
        println("\nSolving model using CPLEX version $(CPLEX.version())...")
    else
        println("\nSolving model...")
    end

    status = @time solve(model.modelname)
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
