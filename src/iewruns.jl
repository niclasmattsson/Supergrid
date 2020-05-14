using Plots, JLD2, FileIO, Plots.PlotMeasures

plotly()

function CAnucleartest()
    # resultslist = Dict()
    # capacity = Dict()
    # energy = Dict()
    JLD2.@load "nuclearcosts2.jld2" resultslist capacity energy
    for nuccost in 8500:500:9000
        options, hourinfo, sets, params = buildsetsparams(carboncap=0.0, hydroinvestmentsallowed=false)
        println("\n\n\nNew run: nuclear cost=$nuccost.")
        params.investcost[:nuclear,:_] = nuccost
        model = buildvarsmodel(options, hourinfo, sets, params)
        println("\nSolving model...")
        status = solve(model.modelname)
        println("\nSolve status: $status")
        resultslist[nuccost] = sum(getvalue(model.vars.Systemcost)) / sum(params.demand) * 1000
        capacity[nuccost] = sum(getvalue(model.vars.Capacity[r,:nuclear,:_]) for r in sets.REGION)
        energy[nuccost] = sum(getvalue(model.vars.Electricity[r,:nuclear,:_,h]) for r in sets.REGION, h in sets.HOUR) / sum(params.demand) 
        JLD2.@save "nuclearcosts2.jld2" resultslist capacity energy
        println("\nReading results...")
        results = readresults(model, status)
        name = autorunname(model.options) * ", nuccost=$nuccost"
        println("\nSaving results to disk...")
        saveresults(results, name, resultsfile="nuclearruns.jld2")
    end
    resultslist, capacity
end

function newrun1!(nuc, solarwind, tm, cap, resultslist, allstatus, path, runsuffix, disabletechs)
    println("\n\n\nNew run: transmission=$tm, cap=$cap, solarwind=$solarwind, nuclear=$nuc.")
    model = buildmodel(regionset=:Eurasia21, islandindexes=[1:8, 9:15, 16:21], hours=1, maxbioenergy=0.05, 
                        carboncap=cap, nuclearallowed=nuc, transmissionallowed=tm, solarwindarea=solarwind, disabletechs=disabletechs)
    println("\nSolving model...")
    status = solve(model.modelname)
    println("\nSolve status: $status")
    resultslist[nuc,solarwind,tm,cap] = sum(getvalue(model.vars.Systemcost))
    allstatus[nuc,solarwind,tm,cap] = status
    JLD2.@save "$(path)supergridcosts1$runsuffix.jld2" resultslist allstatus
    println("\nReading results...")
    results = readresults(model, status)
    name = autorunname(model.options)
    println("\nSaving results to disk...")
    saveresults(results, name, resultsfile="$(path)supergridruns1$runsuffix.jld2")
end

function build_costs_from_runs(runsname, outname)
    path = "D:\\model runs\\"
    runs = listresults(resultsfile="$path$runsname")
    resultslist = Dict()
    allstatus = Dict()
    for (i, runname) in enumerate(runs)
        println("$i/$(length(runs)): $runname")
        r = loadresults(runname, resultsfile="$path$runsname")
        resultslist[runname] = sum(r.Systemcost)
        allstatus[runname] = r.Status
    end
    JLD2.@save "$path$outname" resultslist allstatus
end

function newrun!(namesuffix, options, hourinfo, sets, params, resultslist, allstatus, path, runsuffix)
    name = (namesuffix == "") ? autorunname(options) : autorunname(options) * ", " * namesuffix
    println("\n\n\nNew run: $name.")
    model = buildvarsmodel(options, hourinfo, sets, params)
    println("\nSolving model...")
    status = solve(model.modelname)
    println("\nSolve status: $status")
    resultslist[name] = sum(getvalue(model.vars.Systemcost))
    allstatus[name] = status
    JLD2.@save "$(path)supergridcosts3$runsuffix.jld2" resultslist allstatus
    println("\nReading results...")
    results = readresults(model, status)
    println("\nSaving results to disk...")
    saveresults(results, name, resultsfile="$(path)supergridruns3$runsuffix.jld2")
end

function supergridruns1()
    resultslist = Dict()
    allstatus = Dict()
    path = "D:\\model runs\\"
    runsuffix = "_mar10"
    for tm in [:none, :islands, :all]
        for cap in [1, 0.2, 0.1, 0.05, 0.02, 0.01, 0.005, 0.002, 0.001, 0]
            for solarwind in [1, 2], nuc in [false]
                newrun1!(nuc, solarwind, tm, cap, resultslist, allstatus, path, runsuffix, [:csp])
            end
            for solarwind in [1], nuc in [true]
                newrun1!(nuc, solarwind, tm, cap, resultslist, allstatus, path, runsuffix, [:csp])
            end
            for solarwind in [1, 2], nuc in [false]
                newrun1!(nuc, solarwind, tm, cap, resultslist, allstatus, path, runsuffix, [])
            end
        end
    end
    resultslist, allstatus
end

function supergridruns2()
    resultslist = Dict()
    allstatus = Dict()
    path = "D:\\model runs\\"
    runsuffix = "_mar10"
    for tm in [:none, :islands, :all]
        for cap in [1, 0.2, 0.1, 0.05, 0.02, 0.01, 0.005, 0.002, 0.001, 0]
            for solarwind in [1, 2], nuc in [false]
                options, hourinfo, sets, params = buildsetsparams(regionset=:Eurasia21, islandindexes=[1:8, 9:15, 16:21], hours=1, maxbioenergy=0.05,
                        carboncap=cap, solarwindarea=solarwind, nuclearallowed=nuc, transmissionallowed=tm, disabletechs=[:csp])
                params.transmissioninvestcost .*= 0.5
                params.transmissionfixedcost .*= 0.5
                newrun!("half_transmission_cost", options, hourinfo, sets, params, resultslist, allstatus, path, runsuffix)

                options, hourinfo, sets, params = buildsetsparams(regionset=:Eurasia21, islandindexes=[1:8, 9:15, 16:21], hours=1, maxbioenergy=0.05,
                        carboncap=cap, solarwindarea=solarwind, nuclearallowed=nuc, transmissionallowed=tm, disabletechs=[])
                newrun!("", options, hourinfo, sets, params, resultslist, allstatus, path, runsuffix)
            end
        end
    end
    for tm in [:islands, :all]
        for cap in [0.001]
            for solarwind in [1, 2], nuc in [false]
                for solar in [:high, :mid, :low], battery in [:high, :mid, :low]
                    options, hourinfo, sets, params = buildsetsparams(regionset=:Eurasia21, islandindexes=[1:8, 9:15, 16:21], hours=1, maxbioenergy=0.05,
                            carboncap=cap, solarwindarea=solarwind, nuclearallowed=nuc, transmissionallowed=tm, disabletechs=[:csp])
                    solarbatterycosts!(sets, params, solar, battery)
                    newrun!("solar=$solar, battery=$battery", options, hourinfo, sets, params, resultslist, allstatus, path, runsuffix)
                end
            end
        end
    end
    resultslist, allstatus
end

function solarbatterycosts!(sets, params, solar, battery)
    pvcost = params.investcost[:pv,:a1]
    pvroofcost = params.investcost[:pvroof,:a1]
    batterycost = params.investcost[:battery,:_]
    for c in sets.CLASS[:pv]
        if solar == :high
            params.investcost[:pv,c] = pvcost + 300
            params.investcost[:pvroof,c] = pvroofcost + 300
        elseif solar == :mid
            params.investcost[:pv,c] = pvcost
            params.investcost[:pvroof,c] = pvroofcost
        elseif solar == :low
            params.investcost[:pv,c] = pvcost - 300
            params.investcost[:pvroof,c] = pvroofcost - 300
        end
    end
    if battery == :high
        params.investcost[:battery,:_] = batterycost * 1.5
    elseif battery == :mid
        params.investcost[:battery,:_] = batterycost
    elseif battery == :low
        params.investcost[:battery,:_] = batterycost * 0.5
    end
    nothing
end

function gispaperruns(runsuffix="_nov14", discountrate=0.07)
    path = "D:\\model runs\\"
    resultsfile = "$(path)gispaper_mixes$runsuffix.jld2"
    for carboncap in [0.025], landarea in [1, 2], region in [:China6, :Europe8]
        println("\n\n\nNew run: carboncap=$carboncap, landarea=$landarea, region=$region.")
        runmodel(regionset=region, carboncap=carboncap, discountrate=discountrate,
                        nuclearallowed=false, solarwindarea=landarea, resultsfile=resultsfile);
        if region == :Europe8
            println("\n\n\nNew run: carboncap=$carboncap, landarea=$landarea, region=$region, no transmission.")
            runmodel(regionset=region, carboncap=carboncap, discountrate=discountrate,
                    nuclearallowed=false, solarwindarea=landarea, transmissionallowed=:none, resultsfile=resultsfile);
        end
    end
end

# GIS paper figure 4
function plot_gispaper_mixes1(runsuffix="_nov14", carboncap=0.025, discountrate=0.07)
    path = "D:\\model runs\\"
    resultsfile = "$(path)gispaper_mixes$runsuffix.jld2"
    scen = ["default", "high land"]
    resultsnames = ["discountrate=$discountrate, nuclearallowed=false, carboncap=$carboncap, resultsfile=$resultsfile",
                    "discountrate=$discountrate, nuclearallowed=false, carboncap=$carboncap, resultsfile=$resultsfile, solarwindarea=2"]
    chart_energymix_scenarios(scen, resultsnames, resultsfile, size=(480,550), bar_width=0.7, xlims=(0.3,2.7), title="Europe")
    scen = ["default", "high land"]
    resultsnames = ["regionset=China6, discountrate=$discountrate, nuclearallowed=false, carboncap=$carboncap, resultsfile=$resultsfile",
                    "regionset=China6, discountrate=$discountrate, nuclearallowed=false, carboncap=$carboncap, resultsfile=$resultsfile, solarwindarea=2"]
    chart_energymix_scenarios(scen, resultsnames, resultsfile, size=(480,550), bar_width=0.7, xlims=(0.3,2.7), title="China")
end

# GIS paper figure 5
function plot_gispaper_mixes2(runsuffix="_nov14", carboncap=0.025, discountrate=0.07)
    path = "D:\\model runs\\"
    resultsfile = "$(path)gispaper_mixes$runsuffix.jld2"
    scen = ["default", "no transmission"]
    resultsnames = ["discountrate=$discountrate, nuclearallowed=false, carboncap=$carboncap, resultsfile=$resultsfile",
                    "transmissionallowed=none, discountrate=$discountrate, nuclearallowed=false, carboncap=$carboncap, resultsfile=$resultsfile"]
    chart_energymix_scenarios(scen, resultsnames, resultsfile, size=(480,550), bar_width=0.7, xlims=(0.3,2.7), title="Europe")
end

# GIS paper figure 6
function plot_gispaper_springmonth(runsuffix="_nov14", carboncap=0.025, discountrate=0.07)
    path = "D:\\model runs\\"
    resultsfile = "$(path)gispaper_mixes$runsuffix.jld2"
    r = loadresults("transmissionallowed=none, discountrate=$discountrate, nuclearallowed=false, carboncap=$carboncap, resultsfile=$resultsfile", resultsfile=resultsfile)
    annualelec, capac, tcapac, chart = analyzeresults(r)
    chart(:FRA, xlims=(1872,1872+722), ylims=(0,255))
    chart(:SPA, xlims=(1872,1872+722), ylims=(0,120))
end

# GIS paper figures 3 and 7
function plot_gispaper_classes1(runsuffix="_nov14", carboncap=0.025, discountrate=0.07)
    path = "D:\\model runs\\"
    resultsfile = "$(path)gispaper_mixes$runsuffix.jld2"
    r = loadresults("transmissionallowed=none, discountrate=$discountrate, nuclearallowed=false, carboncap=$carboncap, resultsfile=$resultsfile", resultsfile=resultsfile)
    annualelec, capac, tcapac, chart = analyzeresults(r)
    chart(:TOT)
    chart(:BARS, ylims=(0,1150))
end

# GIS paper figure 3 and 8
function plot_gispaper_classes2(runsuffix="_nov14", carboncap=0.025, discountrate=0.07)
    path = "D:\\model runs\\"
    resultsfile = "$(path)gispaper_mixes$runsuffix.jld2"
    r = loadresults("discountrate=$discountrate, nuclearallowed=false, carboncap=$carboncap, resultsfile=$resultsfile", resultsfile=resultsfile)
    annualelec, capac, tcapac, chart = analyzeresults(r)
    chart(:TOT)
    chart(:BARS, ylims=(0,1150))
end

function mergeresults()
    # JLD2.@load "iewcosts1_0.jld2" resultslist allstatus
    # res0, st0 = resultslist, allstatus
    # JLD2.@load "iewcosts1.jld2" resultslist allstatus
    # resultslist[false, 1, :none, 1.0] = res0[false, 1, :none, 1.0] 
    # allstatus[false, 1, :none, 1.0] = st0[false, 1, :none, 1.0] 
    # JLD2.@save "iewcosts1.jld2" resultslist allstatus
    JLD2.@load "iewcosts2 - part1.jld2" resultslist allstatus
    res1, st1 = resultslist, allstatus
    JLD2.@load "iewcosts2 - part2.jld2" resultslist allstatus
    res2, st2 = resultslist, allstatus
    resultslist = merge(res1, res2)
    allstatus = merge(st1, st2)
    JLD2.@save "iewcosts2.jld2" resultslist allstatus
end

# Figure 2 in the supergrid paper (fig 1 is the eurasia map).
function plot_supergridpaper_lines()
    path = "D:\\model runs\\"
    runsuffix = "_mar10"
    resultsfile = "$(path)supergridruns1$runsuffix.jld2"
    r = loadresults(runname(1, :all, 1.0, false, false, false), resultsfile=resultsfile)
    totaldemand = sum(r.params[:demand])    # 1.975066479481802e7   # (GWh/yr) 
    JLD2.@load "$(path)supergridcosts1$runsuffix.jld2" resultslist allstatus
    res = resultslist
    carboncaps = Any[1000; 200; 100; 50; 20; 10; 5; 2; 1]   

    function getresults(a,b,c,d,e,f)
        cost = get(res, runname(a,b,c,d,e,f), NaN)              # M€/year
        return cost > 1e7 ? NaN : cost/totaldemand*1000     # €/MWh
    end

    resmat2 = [getresults(1, tm, cap/1000, false, false, false) for cap in carboncaps, tm in [:islands, :all]]
    resmat4 = [getresults(2, tm, cap/1000, false, false, false) for cap in carboncaps, tm in [:islands, :all]]
    carboncaps[1] = "none"

    p = plot(string.(carboncaps), [resmat2 resmat4], color=[1 2 1 2], line=[:solid :solid :dash :dash])
    display(plot(p, size=(850,450), ylim=(0,60), 
                    label=["C" "S" "C-Hland" "S-Hland"],
                    line=3, tickfont=14, legendfont=14,
                    titlefont=16, guidefont=14, xlabel="Global CO<sub>2</sub> cap [g CO<sub>2</sub>/kWh]", ylabel="Average system cost [€/MWh]",
                    left_margin=50px, gridlinewidth=1))
    p2 = plot(string.(carboncaps), resmat2, title="Low solar & wind area", label=["" ""])
    p4 = plot(string.(carboncaps), resmat4, title="High solar & wind area", label=[:islands :all])
    display(plot(p2, p4, layout=2, size=(1000,450), ylim=(0,60), line=3, tickfont=14, legendfont=14,
                    titlefont=16, guidefont=14, xlabel="Global CO<sub>2</sub> cap [g CO<sub>2</sub>/kWh]", ylabel="Average system cost [€/MWh]",
                    left_margin=50px, gridlinewidth=1))
end

function plot_supergridpaper_lines_transmission(allowcsp=false, allownuclear=false, halftmcost=false)
    path = "D:\\model runs\\"
    runsuffix = "_mar10"
    csprunnumber = (allowcsp || halftmcost) ? 2 : 1
    resultsfile = "$(path)supergridruns$csprunnumber$runsuffix.jld2"
    r = loadresults(runname(1, :all, 1.0, allowcsp, allownuclear, halftmcost), resultsfile=resultsfile)
    totaldemand = sum(r.params[:demand])    # 1.975066479481802e7   # (GWh/yr) 
    JLD2.@load "$(path)supergridcosts$csprunnumber$runsuffix.jld2" resultslist allstatus
    res = resultslist
    # JLD2.@load "$(path)supergridcosts2$runsuffix.jld2" resultslist allstatus
    # res = merge(res, resultslist)
    carboncaps = Any[1000; 200; 100; 50; 20; 10; 5; 2; 1]
    titletext = "CSP " * (allowcsp ? "" : "not ") * "allowed" * (halftmcost ? ", half transmission cost" : "") * (allownuclear ? ", nuclear allowed" : "")

    function getresults(a,b,c,d,e,f)
        cost = get(res, runname(a,b,c,d,e,f), NaN)              # M€/year
        return cost > 1e7 ? NaN : cost/totaldemand*1000     # €/MWh
    end

    resmat1 = [getresults(1, tm, cap/1000, allowcsp, allownuclear, halftmcost) for cap in carboncaps, tm in [:none, :islands, :all]]
    resmat2 = [getresults(2, tm, cap/1000, allowcsp, allownuclear, halftmcost) for cap in carboncaps, tm in [:none, :islands, :all]]
    carboncaps[1] = "none"

    p = plot(string.(carboncaps), [resmat1 resmat2], color=[3 1 2 3 1 2], line=[:solid :solid :solid :dash :dash :dash])
    display(plot(p, size=(850,450), ylim=(0,60), 
                    label=["R           " "C" "S" "R-Hland" "C-Hland" "S-Hland"],
                    line=3, tickfont=14, legendfont=14,
                    titlefont=16, guidefont=14, xlabel="Global CO<sub>2</sub> cap [g CO<sub>2</sub>/kWh]", ylabel="Average system cost [€/MWh]",
                    left_margin=50px, gridlinewidth=1, title=titletext))
end

runname(land::Int, tm::Symbol, cap::Float64, allowcsp::Bool, allownuclear::Bool, halftmcost::Bool) =
    "regionset=Eurasia21, " * (tm == :all ? "" : "transmissionallowed=$tm, ") *
    (allownuclear ? "" : "nuclearallowed=false, ") * (cap == 1.0 ? "" : "carboncap=$cap, ") * (land == 1 ? "" : "solarwindarea=2, ") *
    (allowcsp ? "" : "disabletechs=Symbol[:csp], ") * "islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]" * (halftmcost ? ", half_transmission_cost" : "")

runname(land::Int, tm::Symbol, solar::Symbol, battery::Symbol) =
    "regionset=Eurasia21, " * (tm == :all ? "" : "transmissionallowed=$tm, ") *
    "nuclearallowed=false, carboncap=0.001, " * (land == 1 ? "" : "solarwindarea=2, ") *
    "disabletechs=Symbol[:csp], islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21], solar=$solar, battery=$battery"

# Figure 4 in the supergrid paper.
function plot_supergridpaper_bubbles()
    path = "D:\\model runs\\"
    runsuffix = "_mar10"
    JLD2.@load "$(path)supergridcosts3$runsuffix.jld2" resultslist allstatus
    res = resultslist
    # showall(keys(res))
    rows = [3 3 3 2 2 2 1 1 1]
    cols = [3 2 1 3 2 1 3 2 1]
    r1 = [res[runname(1,:islands,solar,battery)]/res[runname(1,:all,solar,battery)]-1 for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
    r2 = [res[runname(2,:islands,solar,battery)]/res[runname(2,:all,solar,battery)]-1 for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
    bs = 0.4    # bubble size
    annotations1 = [(rows[i]-0.65*bs*sqrt(r1[i]*100/pi), cols[i], text("$(round(r1[i]*100, digits=1))%", :right)) for i=1:9]
    annotations2 = [(rows[i]-0.65*bs*sqrt(r2[i]*100/pi), cols[i], text("$(round(r2[i]*100, digits=1))%", :right)) for i=1:9]
    s1 = scatter(rows, cols, markersize=reshape(sqrt.(r1*100/pi)*75*bs, (1,9)), annotations=annotations1, xlim=(0.4,3.4), ylim=(0.5,3.5), legend=false,
                    title="Default solar & wind area", xlabel="battery cost", ylabel="solar PV cost", color=1,
                    tickfont=14, guidefont=14)
    xticks!([1,2,3],["low","mid","high"])
    yticks!([1,2,3],["low","mid","high"])
    s2 = scatter(rows, cols, markersize=reshape(sqrt.(r2*100/pi)*75*bs, (1,9)), annotations=annotations2, xlim=(0.4,3.4), ylim=(0.5,3.5), legend=false,
                    title="High solar & wind area", xlabel="battery cost", ylabel="solar PV cost", color=1,
                    tickfont=14, guidefont=14, left_margin=20px)
    xticks!([1,2,3],["low","mid","high"])
    yticks!([1,2,3],["low","mid","high"])
    # display(plot(s2, size=(500,450)))
    display(plot(s1, s2, layout=2, size=(1000,450)))
end

# Figure 3 in the supergrid paper.
function plot_supergridpaper_energymix(cap=0.001, allowcsp=false, allownuclear=false, halftmcost=false)
    path = "D:\\model runs\\"
    runsuffix = "_mar10"
    csprunnumber = (allowcsp || halftmcost) ? 2 : 1
    resultsfile = "$(path)supergridruns$csprunnumber$runsuffix.jld2"
    indices = (cap >= 0.1 || allownuclear) ? collect(1:6) : [2,3,5,6]
    if allownuclear
        indices = indices[indices .<= 3]
    end
    scen = ["R", "C", "S", "R-Hland", "C-Hland", "S-Hland"][indices]
    resultsnames = [runname(1, :none, cap, allowcsp, allownuclear, halftmcost),
                    runname(1, :islands, cap, allowcsp, allownuclear, halftmcost),
                    runname(1, :all, cap, allowcsp, allownuclear, halftmcost),
                    runname(2, :none, cap, allowcsp, allownuclear, halftmcost),
                    runname(2, :islands, cap, allowcsp, allownuclear, halftmcost),
                    runname(2, :all, cap, allowcsp, allownuclear, halftmcost)][indices]
    cap1000 = round(Int, 1000*cap)
    titletext = "CSP " * (allowcsp ? "" : "not ") * "allowed" * (halftmcost ? ", half transmission cost" : "") *
                    (allownuclear ? ", nuclear allowed" : "") * ", $cap1000 g CO<sub>2</sub>/kWh"
    plot_energymix(scen, resultsnames, resultsfile; size=(200+100*length(indices), 550), title=titletext)  #, deletetechs=[1,2,6,7,12])
end

function plot_energymix(scen, resultsnames, resultsfile; deletetechs=[], optionlist...)
    scenelec, demands, hoursperperiod, displayorder, techlabels = iew_getscenarioresults(scen, resultsnames, resultsfile)

    palette = [RGB([216,137,255]/255...), RGB([119,112,71]/255...), RGB([199,218,241]/255...), RGB([149,179,215]/255...),
        RGB([255,255,64]/255...), RGB([240,224,0]/255...), RGB([214,64,64]/255...), RGB([99,172,70]/255...), RGB([255,192,0]/255...), 
        RGB([100,136,209]/255...), RGB([144,213,93]/255...), RGB([148,138,84]/255...), RGB([157,87,205]/255...)]

    deleteat!(palette, deletetechs)
    techlabels = permutedims(deleteat!(vec(techlabels), deletetechs))
    deleteat!(displayorder, deletetechs)

    stackedbar(collect(scenelec[displayorder,:]')/1e6; label=techlabels, size=(600,550), left_margin=20px,
        xticks=(1:length(scen),scen), line=0, tickfont=12, legendfont=12, guidefont=12, color_palette=palette,
        ylabel="[PWh/year]", optionlist...)
    xpos = (1:length(scen))'
    lab = fill("",(1,length(scen)))
    lab[1] = "demand"
    display(plot!([xpos; xpos], [zeros(length(scen))'; demands'*hoursperperiod/1e6], line=3, color=:black, label=lab))
    nothing
end

function iew_readscenariodata(resultname, resultsfile)
    println(resultname, " ", resultsfile)
    results = loadresults(resultname, resultsfile=resultsfile)
    @unpack TECH, REGION, CLASS, HOUR = results.sets
    hoursperperiod = results.hourinfo.hoursperperiod
    totaldemand = sum(results.params[:demand])
    totalelec = [sum(sum(results.Electricity[k,c]) for c in CLASS[k]) for k in TECH]

    techdisplayorder = [:nuclear, :coal, :wind, :offwind, :pv, :pvroof, :csp, :bioCCGT, :gasCCGT, :hydro, :bioGT, :gasGT, :battery]
    techlabels = [k for r=1:1, k in techdisplayorder]
    displayorder = [i for (i,k) in enumerate(TECH), d in techdisplayorder if d == k]

    return totalelec, totaldemand, hoursperperiod, displayorder, techlabels
end

function iew_getscenarioresults(scenarios, resultsnames, resultsfile)
    numscen = length(scenarios)
    scenelec = zeros(13,numscen)
    demands = zeros(numscen)
    hoursperperiod, displayorder, techlabels = nothing, nothing, nothing

    for (i,s) in enumerate(scenarios)
        println("Loading results: $s...")
        totalelec, totaldemand, hoursperperiod, displayorder, techlabels = iew_readscenariodata(resultsnames[i], resultsfile)
        scenelec[:,i] = totalelec
        demands[i] = totaldemand
    end
    return scenelec, demands, hoursperperiod, displayorder, techlabels
end
