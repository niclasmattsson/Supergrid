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
    JLD2.@save "$(path)supergridcosts$runsuffix.jld2" resultslist allstatus
    println("\nReading results...")
    results = readresults(model, status)
    println("\nSaving results to disk...")
    saveresults(results, name, resultsfile="$(path)supergridruns$runsuffix.jld2")
end

function supergridruns1()
    resultslist = Dict()
    allstatus = Dict()
    path = "D:\\model runs\\"
    runsuffix = "_dec6"
    for tm in [:none, :islands, :all]
        for cap in [1, 0.2, 0.1, 0.05, 0.02, 0.01, 0.005, 0.002, 0.001, 0]
            for solarwind in [1, 2], nuc in [false]
                options, hourinfo, sets, params = buildsetsparams(regionset=:Eurasia21,
                    islandindexes=[1:8, 9:15, 16:21], hours=1, maxbioenergy=0.05,
                    sspscenario="ssp2-26", sspyear=2050, datayear=2017,
                    carboncap=cap, solarwindarea=solarwind, nuclearallowed=nuc,
                    transmissionallowed=tm, disabletechs=[:csp])
                newrun!("", options, hourinfo, sets, params, resultslist, allstatus, path, runsuffix)
            end
            for solarwind in [1], nuc in [true]
                options, hourinfo, sets, params = buildsetsparams(regionset=:Eurasia21,
                    islandindexes=[1:8, 9:15, 16:21], hours=1, maxbioenergy=0.05,
                    sspscenario="ssp2-26", sspyear=2050, datayear=2017,
                    carboncap=cap, solarwindarea=solarwind, nuclearallowed=nuc,
                    transmissionallowed=tm, disabletechs=[:csp])
                newrun!("", options, hourinfo, sets, params, resultslist, allstatus, path, runsuffix)
            end
        end
    end
    resultslist, allstatus
end

function supergridruns2()
    path = "D:\\model runs\\"
    runsuffix = "_dec6"
    JLD2.@load "$(path)supergridcosts$runsuffix.jld2" resultslist allstatus
    for tm in [:none, :islands, :all]
        for cap in [1, 0.2, 0.1, 0.05, 0.02, 0.01, 0.005, 0.002, 0.001, 0]
            for solarwind in [1, 2], nuc in [false]
                options, hourinfo, sets, params = buildsetsparams(regionset=:Eurasia21,
                    islandindexes=[1:8, 9:15, 16:21], hours=1, maxbioenergy=0.05,
                    sspscenario="ssp2-26", sspyear=2050, datayear=2017,
                    carboncap=cap, solarwindarea=solarwind, nuclearallowed=nuc,
                    transmissionallowed=tm, disabletechs=[:csp])
                params.transmissioninvestcost .*= 0.5
                params.transmissionfixedcost .*= 0.5
                newrun!("half_transmission_cost", options, hourinfo, sets, params, resultslist, allstatus, path, runsuffix)

                options, hourinfo, sets, params = buildsetsparams(regionset=:Eurasia21,
                    islandindexes=[1:8, 9:15, 16:21], hours=1, maxbioenergy=0.05,
                    sspscenario="ssp2-26", sspyear=2050, datayear=2017,
                    carboncap=cap, solarwindarea=solarwind, nuclearallowed=nuc,
                    transmissionallowed=tm, disabletechs=[])
                newrun!("", options, hourinfo, sets, params, resultslist, allstatus, path, runsuffix)
            end
        end
    end
    resultslist, allstatus
end

function supergridruns3()
    path = "D:\\model runs\\"
    runsuffix = "_dec6"
    JLD2.@load "$(path)supergridcosts$runsuffix.jld2" resultslist allstatus
    for combo in [("ssp2-26", 2017), ("ssp2-26", 1998), ("ssp2-26", 2003), ("ssp1-45", 2017)]
    # for combo in [("ssp2-26", 2003), ("ssp1-45", 2017)]
        sspscen, erayear = combo
        for tm in [:islands, :all], cap in [0.001]
            for solarwind in [1, 2], nuc in [false]
                for solar in [:high, :mid, :low], battery in [:high, :mid, :low]
                    options, hourinfo, sets, params = buildsetsparams(regionset=:Eurasia21,
                        islandindexes=[1:8, 9:15, 16:21], hours=1, maxbioenergy=0.05,
                        sspscenario=sspscen, sspyear=2050, datayear=erayear,
                        carboncap=cap, solarwindarea=solarwind, nuclearallowed=nuc,
                        transmissionallowed=tm, disabletechs=[:csp])
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

function plot_supergridpaper_lines(ssp="ssp2-26", datayear=2017; runsuffix="_dec6")
    path = "D:\\model runs\\"
    resultsfile = "$(path)supergridruns$runsuffix.jld2"
    oldresults = (runsuffix == "_apr14")
    r = loadresults(runname(1, :all, 1.0, ssp, datayear, false, false, false; oldresults=oldresults), resultsfile=resultsfile)
    totaldemand = sum(r.params[:demand])    # 1.975066479481802e7   # (GWh/yr) 
    existinghydro = sumdimdrop(r.Electricity[:hydro,:x0], dims=1)
    JLD2.@load "$(path)supergridcosts$runsuffix.jld2" resultslist allstatus
    res = resultslist
    carboncaps = Any[1000; 200; 100; 50; 20; 10; 5; 2; 1; 0]    

    function getresults(a,b,c,d,e,f,g,h)
        cost = get(res, runname(a,b,c,d,e,f,g,h; oldresults=oldresults), NaN)    # M€/year
        return cost > 1e7 ? NaN : cost/(totaldemand - sum(existinghydro))*1000 # €/MWh
    end

    resmat2 = [getresults(1, tm, cap/1000, ssp, datayear, false, false, false)
                    for cap in carboncaps, tm in [:islands, :all]]
    resmat4 = [getresults(2, tm, cap/1000, ssp, datayear, false, false, false)
                    for cap in carboncaps, tm in [:islands, :all]]
    carboncaps[1] = "none"

    plotly()
    p = plot(string.(carboncaps), [resmat2 resmat4], color=[1 2 1 2], line=[:solid :solid :dash :dash])
    display(plot(p, size=(850,450), ylim=(0,61), 
                    label=["C" "S" "C-Hland" "S-Hland"],
                    line=3, tickfont=14, legendfont=14,
                    titlefont=16, guidefont=14, xlabel="Global CO<sub>2</sub> cap [g CO<sub>2</sub>/kWh]", ylabel="Average system cost [€/MWh]",
                    legend = :outertopright, left_margin=50px, gridlinewidth=1))
    p2 = plot(string.(carboncaps), resmat2, title="Low solar & wind area", label=["" ""])
    p4 = plot(string.(carboncaps), resmat4, title="High solar & wind area", label=["islands" "all"])
    display(plot(p2, p4, layout=2, size=(1000,450), ylim=(0,60), line=3, tickfont=14, legendfont=14,
                    titlefont=16, guidefont=14, xlabel="Global CO<sub>2</sub> cap [g CO<sub>2</sub>/kWh]", ylabel="Average system cost [€/MWh]",
                    legend = :outertopright, left_margin=50px, gridlinewidth=1))
    
end

# Figure 2 in the supergrid paper (fig 1 is the eurasia map).
# SG.plot_supergridpaper_lines_transmission("ssp2-26", 2017, false, false, false, hidetitle=true)
# Supplementary figures:
# S1: SG.plot_supergridpaper_lines_transmission("ssp2-26", 2017, false, false, true, hidescenario=true)
# S2: SG.plot_supergridpaper_lines_transmission("ssp2-26", 2017, false, true, false, hidescenario=true)
# S3: SG.plot_supergridpaper_lines_transmission("ssp2-26", 2017, true, false, false, hidescenario=true)
function plot_supergridpaper_lines_transmission(ssp="ssp2-26", datayear=2017,
            allowcsp=false, allownuclear=false, halftmcost=false;
            hidetitle=false, hidescenario=false, runsuffix="_dec6")
    path = "D:\\model runs\\"
    resultsfile = "$(path)supergridruns$runsuffix.jld2"
    oldresults = (runsuffix == "_apr14")
    r = loadresults(runname(1, :all, 1.0, ssp, datayear, allowcsp, allownuclear, halftmcost; oldresults=oldresults), resultsfile=resultsfile)
    totaldemand = sum(r.params[:demand])    # 1.975066479481802e7   # (GWh/yr) 
    existinghydro = sumdimdrop(r.Electricity[:hydro,:x0], dims=1)
    JLD2.@load "$(path)supergridcosts$runsuffix.jld2" resultslist allstatus
    res = resultslist
    # JLD2.@load "$(path)supergridcosts2$runsuffix.jld2" resultslist allstatus
    # res = merge(res, resultslist)
    carboncaps = Any[1000; 200; 100; 50; 20; 10; 5; 2; 1; 0]
    titletext = "CSP " * (allowcsp ? "" : "not ") * "allowed" *
        (halftmcost ? ", half transmission cost" : "") *
        (allownuclear ? ", nuclear allowed" : "") * 
        (hidescenario ? "" : (oldresults ? " [old results]" : " [$ssp, $datayear]"))
    titletext = hidetitle ? "" : titletext

    function getresults(a,b,c,d,e,f,g,h)
        cost = get(res, runname(a,b,c,d,e,f,g,h; oldresults=oldresults), NaN)    # M€/year
        return cost > 1e7 ? NaN : cost/(totaldemand - sum(existinghydro))*1000 # €/MWh
    end

    resmat1 = [getresults(1, tm, cap/1000, ssp, datayear, allowcsp, allownuclear, halftmcost)
                    for cap in carboncaps, tm in [:none, :islands, :all]]
    resmat2 = [getresults(2, tm, cap/1000, ssp, datayear, allowcsp, allownuclear, halftmcost)
                    for cap in carboncaps, tm in [:none, :islands, :all]]
    carboncaps[1] = "none"

    plotly()
    p = plot(string.(carboncaps), [resmat1 resmat2], color=[3 1 2 3 1 2], line=[:solid :solid :solid :dash :dash :dash])
    display(plot(p, size=(850,500), ylim=(0,81), fg_legend = :transparent,
        label=["R           " "C" "S" "R-Hland" "C-Hland" "S-Hland"],
        line=3, tickfont=14, legendfont=14, yticks=0:10:80, legend = :outertopright, 
        titlefont=16, guidefont=14, xlabel="Global CO<sub>2</sub> cap [g CO<sub>2</sub>/kWh]", ylabel="Average system cost [€/MWh]",
        left_margin=50px, top_margin=10px, right_margin=0px, bottom_margin=8px,
        gridlinewidth=1, title=titletext))
    return [resmat1 100*round.(1 .- resmat2./resmat1, digits=3) resmat2]
end

# Other Supergrid figures:
# Figure S4:
# using GlobalEnergyGIS; GE = GlobalEnergyGIS
# Figures S5 & S6:
# using GlobalEnergyGIS; GE = GlobalEnergyGIS
# GISsolar(gisregion="France13", plotmasks=:onlymasks)
# GISwind(gisregion="France13", plotmasks=:onlymasks)
# GISsolar(gisregion="KZK", plotmasks=:onlymasks)
# GISwind(gisregion="KZK", plotmasks=:onlymasks)
# GISsolar(gisregion="CH_E", plotmasks=:onlymasks)
# GISwind(gisregion="CH_E", plotmasks=:onlymasks)
# Figure S7:
# using GlobalEnergyGIS; GE = GlobalEnergyGIS
# using Plots, Plots.PlotMeasures
# plotly()
# absindex, index, meanwind, annualwind = annualwindindex(gisregion="Eurasia21", sites_quantile=0.25, aggregateregions=[1:8, 9:15, 16:21]);
# plot(1979:2019, absindex, c=[1 3 2], label=["Europe"  "CAS"  "China"], ylabel="[m/s]", tickfont=14, lw=2, legend=:outertopright, size=(800,550), legendfontsize=12, marker=:circle, markersize=3, markerstrokewidth=0, fg_legend = :transparent, title="Average wind speeds from ERA5 data (top 25% of pixels)")

runname(land::Int, tm::Symbol, cap::Float64, ssp::String, datayear::Int, allowcsp::Bool,
        allownuclear::Bool, halftmcost::Bool; oldresults=false) =
    "regionset=Eurasia21, " * (tm == :all ? "" : "transmissionallowed=$tm, ") *
    (datayear == 2017 ? "" : "datayear=$datayear, ") *
    (allownuclear ? "" : "nuclearallowed=false, ") *
    (cap == 1.0 ? "" : "carboncap=$cap, ") *
    (land == 1 ? "" : "solarwindarea=2, ") *
    (allowcsp ? "" : "disabletechs=$(oldresults ? "Symbol" : "")[:csp], ") *
    (ssp == "ssp2-34" ? "" : "sspscenario=$ssp, ") *
    "islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]" *
    (halftmcost ? ", half_transmission_cost" : "")

runname(land::Int, tm::Symbol, ssp::String, datayear::Int, solar::Symbol, battery::Symbol;
        oldresults=false) =
    "regionset=Eurasia21, " * (tm == :all ? "" : "transmissionallowed=$tm, ") *
    (datayear == 2017 ? "" : "datayear=$datayear, ") *
    "nuclearallowed=false, carboncap=0.001, " *
    (land == 1 ? "" : "solarwindarea=2, ") *
    "disabletechs=$(oldresults ? "Symbol" : "")[:csp], " *
    (ssp == "ssp2-34" ? "" : "sspscenario=$ssp, ") *
    "islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21], solar=$solar, battery=$battery"

# Figure 4 in the supergrid paper.
# SG.plot_supergridpaper_bubbles("ssp2-26", 2017, hidescenario=true)
# Supplementary figure S4, S5, S6:
# SG.plot_supergridpaper_bubbles("ssp1-45", 2017, hidescenario=false)
# SG.plot_supergridpaper_bubbles("ssp2-26", 1998, hidescenario=false)
# SG.plot_supergridpaper_bubbles("ssp2-26", 2003, hidescenario=false)
function plot_supergridpaper_bubbles(ssp="ssp2-34", datayear=2017;
                hidescenario=false, runsuffix="_dec6")
    path = "D:\\model runs\\"
    JLD2.@load "$(path)supergridcosts$runsuffix.jld2" resultslist allstatus
    oldresults = (runsuffix == "_apr14")
    res = resultslist
    # showall(keys(res))
    rows = [3 3 3 2 2 2 1 1 1]
    cols = [3 2 1 3 2 1 3 2 1]
    r1 = [res[runname(1,:islands,ssp,datayear,solar,battery; oldresults=oldresults)] /
            res[runname(1,:all,ssp,datayear,solar,battery; oldresults=oldresults)]-1
                for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
    r2 = [res[runname(2,:islands,ssp,datayear,solar,battery; oldresults=oldresults)] /
            res[runname(2,:all,ssp,datayear,solar,battery; oldresults=oldresults)]-1
                for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
    bs = 0.4    # bubble size
    annotations1 = [(rows[i]-0.65*bs*sqrt(r1[i]*100/pi), cols[i], text("$(round(r1[i]*100, digits=1))%", :right)) for i=1:9]
    annotations2 = [(rows[i]-0.65*bs*sqrt(r2[i]*100/pi), cols[i], text("$(round(r2[i]*100, digits=1))%", :right)) for i=1:9]
    titlesuffix = hidescenario ? "" : (oldresults ? " [old results]" : " [$ssp, $datayear]")
    s1 = scatter(rows, cols, markersize=reshape(sqrt.(r1*100/pi)*75*bs, (1,9)),
        annotations=annotations1, xlim=(0.4,3.4), ylim=(0.5,3.5), legend=false,
        title="Default solar & wind area" * titlesuffix,
        xlabel="battery cost", ylabel="solar PV cost", color=1, tickfont=14, guidefont=14)
    xticks!([1,2,3],["low","mid","high"])
    yticks!([1,2,3],["low","mid","high"])
    s2 = scatter(rows, cols, markersize=reshape(sqrt.(r2*100/pi)*75*bs, (1,9)),
        annotations=annotations2, xlim=(0.4,3.4), ylim=(0.5,3.5), legend=false,
        title="High solar & wind area" * titlesuffix,
        xlabel="battery cost", ylabel="solar PV cost", color=1, tickfont=14, guidefont=14,
        left_margin=20px)
    xticks!([1,2,3],["low","mid","high"])
    yticks!([1,2,3],["low","mid","high"])
    # display(plot(s2, size=(500,450)))
    display(plot(s1, s2, layout=2, size=(1000,450)))
end

function plot_supergridpaper_bubbles_abscost(transmission=:all, ssp="ssp2-34", datayear=2017;
            hidescenario=false, runsuffix="_dec6")
    path = "D:\\model runs\\"
    JLD2.@load "$(path)supergridcosts$runsuffix.jld2" resultslist allstatus
    oldresults = (runsuffix == "_apr14")
    res = resultslist
    # showall(keys(res))
    rows = [3 3 3 2 2 2 1 1 1]
    cols = [3 2 1 3 2 1 3 2 1]
    r1 = [res[runname(1,transmission,ssp,datayear,solar,battery; oldresults=oldresults)]/1e6
        for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
    r2 = [res[runname(2,transmission,ssp,datayear,solar,battery; oldresults=oldresults)]/1e6
        for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
    bs = 0.4    # bubble size
    annotations1 = [(rows[i]-0.65*bs*sqrt(r1[i]/pi), cols[i], text("$(round(r1[i], digits=3))", :right)) for i=1:9]
    annotations2 = [(rows[i]-0.65*bs*sqrt(r2[i]/pi), cols[i], text("$(round(r2[i], digits=3))", :right)) for i=1:9]
    titlesuffix = hidescenario ? "" : (oldresults ? " [old results]" : " [$transmission, $ssp, $datayear]")
    s1 = scatter(rows, cols, markersize=reshape(sqrt.(r1/pi)*75*bs, (1,9)),
    annotations=annotations1, xlim=(0.4,3.4), ylim=(0.5,3.5), legend=false,
    title="Default area" * titlesuffix,
    xlabel="battery cost", ylabel="solar PV cost", color=1, tickfont=14, guidefont=14)
    xticks!([1,2,3],["low","mid","high"])
    yticks!([1,2,3],["low","mid","high"])
    s2 = scatter(rows, cols, markersize=reshape(sqrt.(r2/pi)*75*bs, (1,9)),
    annotations=annotations2, xlim=(0.4,3.4), ylim=(0.5,3.5), legend=false,
    title="High area" * titlesuffix,
    xlabel="battery cost", ylabel="solar PV cost", color=1, tickfont=14, guidefont=14,
    left_margin=20px)
    xticks!([1,2,3],["low","mid","high"])
    yticks!([1,2,3],["low","mid","high"])
    # display(plot(s2, size=(500,450)))
    display(plot(s1, s2, layout=2, size=(1000,450)))
end

function plot_supergridpaper_all_energymixes()
    # PAPER VERSIONS (no R scenario, unused legend techs removed)
    # plot_supergridpaper_energymix("ssp2-34", 2018, false, false, false,
    #     indices=[2,3,5,6], deletetechs=[1,2,6,7,12], runsuffix="_apr14")
    # plot_supergridpaper_energymix("ssp2-34", 2018, true, false, false,
    #     indices=[2,3,4,5,6], deletetechs=[1,2,12], runsuffix="_apr14")
    # plot_supergridpaper_energymix("ssp2-34", 2018, false, true, false,
    #     indices=[1,2,3,4,5,6], deletetechs=[2,6,7,12], runsuffix="_apr14")
    # plot_supergridpaper_energymix("ssp2-34", 2018, false, false, true,
    #     indices=[2,3,4,5,6], deletetechs=[1,2,6,7,12], runsuffix="_apr14")   

    # DISCUSSION VERSIONS (only infeasible runs removed)
    plot_supergridpaper_energymix("ssp2-26", 2017, false, false, false,
        indices=[2,3,4,5,6], runsuffix="_dec6")
    plot_supergridpaper_energymix("ssp2-26", 2017, true, false, false,
        indices=[2,3,4,5,6], runsuffix="_dec6")
    plot_supergridpaper_energymix("ssp2-26", 2017, false, true, false,
        indices=[1,2,3,4,5,6], runsuffix="_dec6")
    plot_supergridpaper_energymix("ssp2-26", 2017, false, false, true,
        indices=[2,3,4,5,6], runsuffix="_dec6")
    # plot_supergridpaper_energymix("ssp2-26", 2017, false, false, false,
    #     indices=[2,3,5,6], runsuffix="_dec6",
    #     extrasuffix=", solar=mid, battery=mid", ylims=(0,34))
    # plot_supergridpaper_energymix("ssp2-26", 1998, false, false, false,
    #     indices=[2,3,5,6], runsuffix="_dec6",
    #     extrasuffix=", solar=mid, battery=mid", ylims=(0,34))
    # plot_supergridpaper_energymix("ssp2-26", 2003, false, false, false,
    #     indices=[2,3,5,6], runsuffix="_dec6",
    #     extrasuffix=", solar=mid, battery=mid", ylims=(0,34))
    # plot_supergridpaper_energymix("ssp1-45", 2017, false, false, false,
    #     indices=[2,3,5,6], runsuffix="_dec6",
    #     extrasuffix=", solar=mid, battery=mid", ylims=(0,34))
end

# Figure 3 in the supergrid paper.
# SG.plot_supergridpaper_energymix("ssp2-26", 2017, false, false, false, indices=[2,3,5,6], deletetechs=[1,2,6,7,12], hidetitle=true, runsuffix="_dec6")
function plot_supergridpaper_energymix(ssp="ssp2-26", datayear=2017, allowcsp=false,
            allownuclear=false, halftmcost=false;
            cap=0.001, indices=collect(1:6), deletetechs=[2,12],
            runsuffix="_dec6", extrasuffix="", hidetitle=false, figoptions...)
    path = "D:\\model runs\\"
    resultsfile = "$(path)supergridruns$runsuffix.jld2"
    oldresults = (runsuffix == "_apr14")
    # indices = (cap >= 0.1 || allownuclear) ? collect(1:6) : [2,3,5,6]
    if allownuclear
        indices = indices[indices .<= 3]
    end
    scen = ["R", "C", "S", "R-Hland", "C-Hland", "S-Hland"][indices]
    resultsnames = [
        runname(1, :none, cap, ssp, datayear, allowcsp, allownuclear, halftmcost; oldresults=oldresults),
        runname(1, :islands, cap, ssp, datayear, allowcsp, allownuclear, halftmcost; oldresults=oldresults),
        runname(1, :all, cap, ssp, datayear, allowcsp, allownuclear, halftmcost; oldresults=oldresults),
        runname(2, :none, cap, ssp, datayear, allowcsp, allownuclear, halftmcost; oldresults=oldresults),
        runname(2, :islands, cap, ssp, datayear, allowcsp, allownuclear, halftmcost; oldresults=oldresults),
        runname(2, :all, cap, ssp, datayear, allowcsp, allownuclear, halftmcost; oldresults=oldresults)
    ][indices] .* extrasuffix
    cap1000 = round(Int, 1000*cap)
    titletext = "CSP " * (allowcsp ? "" : "not ") * "allowed" *
        (halftmcost ? ", half transmission cost" : "") *
        (allownuclear ? ", nuclear allowed" : "") * 
        ", $cap1000 g CO<sub>2</sub>/kWh" * 
        (oldresults ? " [old results]" : " [$ssp, $datayear]")
    titletext = hidetitle ? "" : titletext
    plot_energymix(scen, resultsnames, resultsfile; size=(200+100*length(indices), 550),
        title=titletext, deletetechs=deletetechs, figoptions...)
    # plot_energymix(["default land", "high land"],
    #     ["regionset=Eurasia21, transmissionallowed=islands, nuclearallowed=false, carboncap=0.001, disabletechs=Symbol[:csp], islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21], solar=low, battery=high",
    #      "regionset=Eurasia21, transmissionallowed=islands, nuclearallowed=false, carboncap=0.001, solarwindarea=2, disabletechs=Symbol[:csp], islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21], solar=low, battery=high"],
    #     resultsfile; size=(400, 550), title="Solar low cost, battery high cost", deletetechs=[1,2,6,7,12])
end

function plot_energymix(scen, resultsnames, resultsfile; deletetechs=[], optionlist...)
    scenelec, demands, hoursperperiod, displayorder, techlabels = iew_getscenarioresults(scen, resultsnames, resultsfile)

    palette = [RGB([216,137,255]/255...), RGB([119,112,71]/255...), RGB([199,218,241]/255...), RGB([149,179,215]/255...),
        RGB([255,255,64]/255...), RGB([240,224,0]/255...), RGB([214,64,64]/255...), RGB([99,172,70]/255...), RGB([255,192,0]/255...), 
        RGB([100,136,209]/255...), RGB([144,213,93]/255...), RGB([148,138,84]/255...), RGB([157,87,205]/255...)]

    deleteat!(palette, deletetechs)
    techlabels = permutedims(deleteat!(vec(techlabels), deletetechs))
    deleteat!(displayorder, deletetechs)

    display(demands'*hoursperperiod/1e6)
    display(techlabels)
    display(scen)
    display(collect(scenelec[displayorder,:]')/1e6)
    stackedbar(collect(scenelec[displayorder,:]')/1e6; label=string.(techlabels),
        size=(600,550), left_margin=20px, fg_legend = :transparent,
        xticks=(1:length(scen),scen), line=0, tickfont=12, legendfont=12, guidefont=12,
        color_palette=palette, ylabel="[PWh/year]", legend=:outertopright, optionlist...)
    xpos = (1:length(scen))'
    lab = fill("",(1,length(scen)))
    lab[1] = "demand"
    display(plot!([xpos; xpos], [zeros(length(scen))'; demands'*hoursperperiod/1e6], line=3, color=:black, label=lab))
    nothing
end

function regionalcosts(ssp="ssp2-34", allowcsp=false, allownuclear=false, halftmcost=false; cap=0.001, indices=collect(1:6), runsuffix="_apr14")
    path = "D:\\model runs\\"
    resultsfile = "$(path)supergridruns$runsuffix.jld2"
    # indices = (cap >= 0.1 || allownuclear) ? collect(1:6) : [2,3,5,6]
    if allownuclear
        indices = indices[indices .<= 3]
    end
    islandindexes=[1:8, 9:15, 16:21, 1:21]
    scen = ["R", "C", "S", "R-Hland", "C-Hland", "S-Hland"][indices]
    resultsnames = [runname(1, :none, cap, ssp, allowcsp, allownuclear, halftmcost),
                    runname(1, :islands, cap, ssp, allowcsp, allownuclear, halftmcost),
                    runname(1, :all, cap, ssp, allowcsp, allownuclear, halftmcost),
                    runname(2, :none, cap, ssp, allowcsp, allownuclear, halftmcost),
                    runname(2, :islands, cap, ssp, allowcsp, allownuclear, halftmcost),
                    runname(2, :all, cap, ssp, allowcsp, allownuclear, halftmcost)][indices]
    for resultname in resultsnames
        println(resultname, " ", resultsfile)
        r = loadresults(resultname, resultsfile=resultsfile)
        existinghydro = sumdimdrop(r.Electricity[:hydro,:x0], dims=1)
        elec = sum(r.Electricity[k,c] for k in r.sets.TECH for c in r.sets.CLASS[k])
        annualelec = sumdimdrop(elec, dims=1)
        demand = sumdimdrop(r.params[:demand], dims=2)
        cost_prod = r.Systemcost ./ (annualelec - existinghydro) * 1000
        cost_dem = r.Systemcost ./ (demand - existinghydro) * 1000
        regcost_prod = [sum(r.Systemcost[is]) ./ sum(annualelec[is] - existinghydro[is]) * 1000 for is in islandindexes]
        regcost_dem = [sum(r.Systemcost[is]) ./ sum(demand[is] - existinghydro[is]) * 1000 for is in islandindexes]
        # @show regcost_prod
        @show regcost_dem
        println()
    end
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
