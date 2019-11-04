using Plots, JLD2, FileIO, Plots.PlotMeasures

plotly()

function CAnucleartest()
	# resultslist = Dict()
	# capacity = Dict()
	# energy = Dict()
	@load "nuclearcosts2.jld2" resultslist capacity energy
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
		@save "nuclearcosts2.jld2" resultslist capacity energy
		println("\nReading results...")
		results = readresults(model, status)
		name = autorunname(model.options) * ", nuccost=$nuccost"
		println("\nSaving results to disk...")
		saveresults(results, name, resultsfile="nuclearruns.jld2")
	end
	resultslist, capacity
end

function FHnuclearextraruns()
	for nuc in [true, false]
		for tm in [:islands, :all]
			println("\n\n\nNew run: nuclear=$nuc, transmission=$tm")
			runmodel(regionset=:eurasia21, carboncap=0, nuclearallowed=nuc, hydroinvestmentsallowed=false, transmissionallowed=tm,
						resultsfile="FHnuclearextraruns.jld2");  # globalnuclearlimit=200,
		end
	end
end

function plot_FHnuclearextraruns_energymix()
	scen = ["Islands - no nuclear", "Supergrid - no nuclear", "Islands - 200GW nuclear", "Supergrid - 200GW nuclear", "Islands - unlimited nuclear", "Supergrid - unlimited nuclear"]
	resultsnames = ["regionset=eurasia21, transmissionallowed=islands, nuclearallowed=false, carboncap=0, resultsfile=FHnuclearextraruns.jld2, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]",
					"regionset=eurasia21, nuclearallowed=false, carboncap=0, resultsfile=FHnuclearextraruns.jld2, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]",
					"regionset=eurasia21, transmissionallowed=islands, globalnuclearlimit=200, carboncap=0, resultsfile=FHnuclearextraruns.jld2, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]",
					"regionset=eurasia21, globalnuclearlimit=200, carboncap=0, resultsfile=FHnuclearextraruns.jld2, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]",
					"regionset=eurasia21, transmissionallowed=islands, carboncap=0, resultsfile=FHnuclearextraruns.jld2, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]",
					"regionset=eurasia21, carboncap=0, resultsfile=FHnuclearextraruns.jld2, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]"]
	resultsfile = "FHnuclearextraruns.jld2"
	plot_energymix(scen, resultsnames, resultsfile)
	# plot_energymix(scen[1,2,5,6], resultsnames[1,2,5,6], resultsfile)
end

function supergridruns1(hourinterval)
	resultslist = Dict()
	allstatus = Dict()
	path = "D:\\model runs\\"
	runsuffix = "_oct31"
	runcount = 0
	for nuc in [false]
		for solarwind in [1, 2]
			for tm in [:none, :islands, :all]
				for cap in [1, 0.2, 0.1, 0.05, 0.02, 0.01, 0.005, 0.002, 0.001, 0]
					# runcount += 1
					# runcount in [1] && continue
					println("\n\n\nNew run: nuclear=$nuc, solarwind=$solarwind, transmission=$tm, cap=$cap.")
					model = buildmodel(regionset=:Eurasia21, islandindexes=[1:8, 9:15, 16:21], hours=hourinterval, maxbioenergy=0.05, 
										carboncap=cap, nuclearallowed=nuc, transmissionallowed=tm, solarwindarea=solarwind)
					println("\nSolving model...")
					status = solve(model.modelname)
					println("\nSolve status: $status")
					resultslist[nuc,solarwind,tm,cap] = sum(getvalue(model.vars.Systemcost))
					allstatus[nuc,solarwind,tm,cap] = status
					@save "$(path)supergridcosts1$runsuffix.jld2" resultslist allstatus
					println("\nReading results...")
					results = readresults(model, status)
					name = autorunname(model.options)
					println("\nSaving results to disk...")
					saveresults(results, name, resultsfile="$(path)supergridruns1$runsuffix.jld2")
				end
			end
		end
	end
	resultslist, allstatus
end

function supergridruns2(hourinterval)
	resultslist = Dict()
	allstatus = Dict()
	path = "D:\\model runs\\"
	runsuffix = "_oct31"
	for nuc in [false]
		for solarwind in [1, 2]
			for tm in [:islands, :all]
				for cap in [0.001]
					options, hourinfo, sets, params = buildsetsparams(hours=hourinterval, carboncap=cap, maxbioenergy=0.05,
											regionset=:Eurasia21, islandindexes=[1:8, 9:15, 16:21], 
											solarwindarea=solarwind, nuclearallowed=nuc, transmissionallowed=tm)
					pvcost = params.investcost[:pv,:a1]
					pvroofcost = params.investcost[:pvroof,:a1]
					batterycost = params.investcost[:battery,:_]
					for solar in [:high, :mid, :low]
						for battery in [:high, :mid, :low]
							println("\n\n\nNew run: nuclear=$nuc, solarwind=$solarwind, transmission=$tm, cap=$cap, solar=$solar, battery=$battery.")
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
							model = buildvarsmodel(options, hourinfo, sets, params)
							println("\nSolving model...")
							status = solve(model.modelname)
							println("\nSolve status: $status")
							resultslist[solarwind,tm,cap,solar,battery] = sum(getvalue(model.vars.Systemcost))
							allstatus[solarwind,tm,cap,solar,battery] = status
							@save "$(path)supergridcosts2$runsuffix.jld2" resultslist allstatus
							println("\nReading results...")
							results = readresults(model, status)
							name = autorunname(model.options) * ", solarwind=$solarwind, solar=$solar, battery=$battery"
							println("\nSaving results to disk...")
							saveresults(results, name, resultsfile="$(path)supergridruns2$runsuffix.jld2")
						end
					end
				end
			end
		end
	end
	resultslist, allstatus
end

function supergridruns_biotest(hourinterval)
	results = Dict()
	allstatus = Dict()
	path = "D:\\model runs\\"
	for bio in [0, 0.025, 0.05, 0.075, 0.1, 0.15, 0.2, 0.3]
		for tm in [:islands, :all]
			for cap in [0.005, 0]
				println("\n\n\nNew run: bio=$bio, transmission=$tm, cap=$cap.")
				model = buildmodel(hours=hourinterval, carboncap=cap, maxbioenergy=bio, 
									nuclearallowed=false, transmissionallowed=tm)
				println("\nSolving model...")
				status = solve(model.modelname)
				println("\nSolve status: $status")
				results[bio,tm,cap] = sum(getvalue(model.vars.Systemcost))
				allstatus[bio,tm,cap] = status
				@save "$(path)supergridruns_biotest_$(hourinterval)h.jld2" results allstatus
			end
		end
	end
	results, allstatus
end

function gispaperruns(runsuffix="_oct31")
	path = "D:\\model runs\\"
	resultsfile = "$(path)gispaper_mixes$runsuffix.jld2"
	for region in [:China6, :Europe8], carboncap in [0.025, 0.005, 0.001], landarea in [1, 2]
		println("\n\n\nNew run: region=$region, carboncap=$carboncap, landarea=$landarea.")
		runmodel(regionset=region, carboncap=carboncap, discountrate=0.07,
						nuclearallowed=false, solarwindarea=landarea, resultsfile=resultsfile);
		println("\n\n\nNew run: region=$region, carboncap=$carboncap, landarea=$landarea, no transmission.")
		runmodel(regionset=region, carboncap=carboncap, discountrate=0.07,
				nuclearallowed=false, solarwindarea=landarea, transmissionallowed=:none, resultsfile=resultsfile);
	end
end

# GIS paper figure 4
function plot_gispaper_mixes1(runsuffix="_oct31", carboncap=0.025)
	path = "D:\\model runs\\"
	resultsfile = "$(path)gispaper_mixes$runsuffix.jld2"
	scen = ["default", "high land"]
	resultsnames = ["discountrate=0.07, nuclearallowed=false, carboncap=$carboncap, resultsfile=$resultsfile",
					"discountrate=0.07, nuclearallowed=false, carboncap=$carboncap, resultsfile=$resultsfile, solarwindarea=2"]
	chart_energymix_scenarios(scen, resultsnames, resultsfile, size=(500,550), xlims=(0.3,2.7), title="Europe")
	scen = ["default", "high land"]
	resultsnames = ["regionset=China6, discountrate=0.07, nuclearallowed=false, carboncap=$carboncap, resultsfile=$resultsfile",
					"regionset=China6, discountrate=0.07, nuclearallowed=false, carboncap=$carboncap, resultsfile=$resultsfile, solarwindarea=2"]
	chart_energymix_scenarios(scen, resultsnames, resultsfile, size=(500,550), xlims=(0.3,2.7), title="China")
end

# GIS paper figure 5
function plot_gispaper_mixes2(runsuffix="_oct31", carboncap=0.025)
	path = "D:\\model runs\\"
	resultsfile = "$(path)gispaper_mixes$runsuffix.jld2"
	scen = ["default", "no transmission"]
	resultsnames = ["discountrate=0.07, nuclearallowed=false, carboncap=$carboncap, resultsfile=$resultsfile",
					"regionset=europe8, transmissionallowed=none, discountrate=0.07, nuclearallowed=false, carboncap=$carboncap, resultsfile=$resultsfile"]
	chart_energymix_scenarios(scen, resultsnames, resultsfile, size=(500,550), xlims=(0.3,2.7), title="Europe")
end

# GIS paper figure 6
function plot_gispaper_springmonth(runsuffix="_oct31", carboncap=0.025)
	path = "D:\\model runs\\"
	resultsfile = "$(path)gispaper_mixes$runsuffix.jld2"
	r = loadresults("regionset=europe8, transmissionallowed=none, discountrate=0.07, nuclearallowed=false, carboncap=$carboncap, resultsfile=$resultsfile", resultsfile=resultsfile)
	annualelec, capac, tcapac, chart = analyzeresults(r)
	chart(:FRA, xlims=(1872,1872+722), ylims=(0,207))
end

# GIS paper figures 3 and 7
function plot_gispaper_classes1(runsuffix="_oct31", carboncap=0.025)
	path = "D:\\model runs\\"
	resultsfile = "$(path)gispaper_mixes$runsuffix.jld2"
	r = loadresults("transmissionallowed=none, discountrate=0.07, nuclearallowed=false, carboncap=$carboncap, resultsfile=$resultsfile", resultsfile=resultsfile)
	annualelec, capac, tcapac, chart = analyzeresults(r)
	chart(:TOT)
	chart(:BARS, ylims=(0,1150))
end

# GIS paper figure 3 and 8
function plot_gispaper_classes2(runsuffix="_oct31", carboncap=0.025)
	path = "D:\\model runs\\"
	resultsfile = "$(path)gispaper_mixes$runsuffix.jld2"
	r = loadresults("discountrate=0.07, nuclearallowed=false, carboncap=$carboncap, resultsfile=$resultsfile", resultsfile=resultsfile)
	annualelec, capac, tcapac, chart = analyzeresults(r)
	chart(:TOT)
	chart(:BARS, ylims=(0,1150))
end

function mergeresults()
	# @load "iewcosts1_0.jld2" resultslist allstatus
	# res0, st0 = resultslist, allstatus
	# @load "iewcosts1.jld2" resultslist allstatus
	# resultslist[false, 1, :none, 1.0] = res0[false, 1, :none, 1.0] 
	# allstatus[false, 1, :none, 1.0] = st0[false, 1, :none, 1.0] 
	# @save "iewcosts1.jld2" resultslist allstatus
	@load "iewcosts2 - part1.jld2" resultslist allstatus
	res1, st1 = resultslist, allstatus
	@load "iewcosts2 - part2.jld2" resultslist allstatus
	res2, st2 = resultslist, allstatus
	resultslist = merge(res1, res2)
	allstatus = merge(st1, st2)
	@save "iewcosts2.jld2" resultslist allstatus
end

function plot_lines_v2()
	totaldemand = 1.8695380613113698e7	# (GWh/yr) r = loadresults("nuclearallowed=false", resultsfile="iewruns1.jld2");  sum(r.params[:demand])
	@load "iewcosts1.jld2" resultslist allstatus
	res = resultslist
	carboncaps = [1000; 200; 100; 50; 20; 10; 5; 2; 1; 0]	
	res0 = get(res,(true,1,:all,1),0)
	if res0 == 0
		res0 = get(res,(false,1,:all,1),0)
		res0 == 0 && error("No results for base case!")
	end
	function getresults(a,b,c,d)
		cost = get(res,(a,b,c,d),NaN)						# M€/year
		return cost > 1e7 ? NaN : cost/totaldemand*1000		# €/MWh
	end
	resmat1 = [getresults(true,1,tm,cap/1000) for cap in carboncaps, tm in [:none, :islands, :all]]
	resmat2 = [getresults(false,1,tm,cap/1000) for cap in carboncaps, tm in [:none, :islands, :all]]
	resmat3 = [getresults(true,4,tm,cap/1000) for cap in carboncaps, tm in [:none, :islands, :all]]
	resmat4 = [getresults(false,4,tm,cap/1000) for cap in carboncaps, tm in [:none, :islands, :all]]
	p1 = plot(string.(carboncaps), resmat1, title="nuclear, default solar & wind area")
	p2 = plot(string.(carboncaps), resmat2, title="no nuclear, default solar & wind area")
	p3 = plot(string.(carboncaps), resmat3, title="nuclear, high solar & wind area")
	p4 = plot(string.(carboncaps), resmat4, title="no nuclear, high solar & wind area")
	display(plot(p2, p4, layout=2, size=(1850,950), ylim=(0,120), label=[:none :islands :all], line=3, tickfont=16, legendfont=16,
					titlefont=20, guidefont=16, xlabel="Global CO2 cap [g CO2/kWh]", ylabel="Average system cost [€/MWh]"))
	# display(plot(p3, p4, layout=2, size=(1850,950), ylim=(0.9,2.5), label=[:none :islands :all], line=3, tickfont=16, legendfont=16,
	# 				titlefont=20, guidefont=16, xlabel="g CO2/kWh", ylabel="relative cost"))
end

function plot_lines_hydro()
	@load "iewcosts1.jld2" resultslist allstatus
	res = resultslist
	carboncaps = [1000; 200; 100; 50; 20; 10; 5; 2; 1; 0]	
	res0 = get(res,(true,1,:all,1),0)
	if res0 == 0
		res0 = get(res,(false,1,:all,1),0)
		res0 == 0 && error("No results for base case!")
	end
	@load "iewcosts1_hydro.jld2" resultslist allstatus
	resh = resultslist
	function getresults(res,a,b,c,d)
		out = get(res,(a,b,c,d),NaN)
		return out > 1e7 ? NaN : out/res0
	end
	resmat1 = [getresults(res,false,1,tm,cap/1000) for cap in carboncaps, tm in [:none, :islands, :all]]
	resmat2 = [getresults(resh,false,1,tm,cap/1000) for cap in carboncaps, tm in [:none, :islands, :all]]
	p1 = plot(string.(carboncaps), resmat1, title="no nuclear, existing hydro")
	p2 = plot(string.(carboncaps), resmat2, title="no nuclear, existing hydro + investments")
	display(plot(p1, p2, layout=2, size=(1850,950), ylim=(0.9,2.5), label=[:none :islands :all], line=3, tickfont=16, legendfont=16,
					titlefont=20, guidefont=16, xlabel="Global CO2 constraint [g CO2/kWh]", ylabel="relative cost"))
end

# using JLD2, Plots; @load "iewruns1_1h.jld2" results allstatus; plotly()
function plot_lines_v1()
	totaldemand = 1.8695380613113698e7	# (GWh/yr) r = loadresults("nuclearallowed=false", resultsfile="iewruns1.jld2");  sum(r.params[:demand])
	@load "iewruns1_1h.jld2" results allstatus
	res = results
	carboncaps = [1000; 200; 100; 50; 20; 10; 5; 2; 1; 0]	
	res0 = res[true,:all,1]
	resmat1 = [res[true,tm,cap/1000]/totaldemand*1000 for cap in carboncaps, tm in [:none, :islands, :all]]
	resmat2 = [res[false,tm,cap/1000]/totaldemand*1000 for cap in carboncaps, tm in [:none, :islands, :all]]
	p1 = plot(string.(carboncaps), resmat1, title="nuclear")
	p2 = plot(string.(carboncaps), resmat2, title="no nuclear")
	display(plot(p1, p2, layout=2, size=(1850,950), ylim=(0,120), label=[:none :islands :all], line=3, tickfont=16, legendfont=16,
					titlefont=20, guidefont=16, xlabel="Global CO2 cap [g CO2/kWh]", ylabel="Average system cost [€/MWh]"))
end

# Doesn't work because it refers to nuclear runs that were not performed, but this chart is not included in the paper.
function plot_lines1_paper()
	totaldemand = 1.8695380613113698e7	# (GWh/yr) r = loadresults("nuclearallowed=false", resultsfile="iewruns1.jld2");  sum(r.params[:demand])
	@load "iewcosts1_new.jld2" resultslist allstatus
	res = resultslist
	# showall(keys(res))
	carboncaps = Any[1000; 200; 100; 50; 20; 10; 5; 2; 1]	
	res0 = res[true,:all,1]
	resmat1 = [res[true,tm,cap/1000]/totaldemand*1000 for cap in carboncaps, tm in [:islands, :all]]
	resmat2 = [res[false,tm,cap/1000]/totaldemand*1000 for cap in carboncaps, tm in [:islands, :all]]
	carboncaps[1] = "none"
	display([resmat2 resmat1])
	p = plot(string.(carboncaps), [resmat2 resmat1], color=[1 2 1 2], line=[:solid :solid :dash :dash])
	display(plot(p, size=(1000,450), ylim=(0,70), 
					label=["Is-lowL - no nuclear" "Sup-lowL - no nuclear" "Is-lowL - unlimited nuclear" "Sup-lowL - unlimited nuclear"],
					line=3, tickfont=14, legendfont=14,
					titlefont=16, guidefont=14, xlabel="Global CO2 cap [g CO2/kWh]", ylabel="Average system cost [€/MWh]",
					left_margin=50px, gridlinewidth=1))
end

# Figure 2 in the supergrid paper (fig 1 is the eurasia map).
function plot_supergridpaper_lines()
	path = "D:\\model runs\\"
	runsuffix = "_oct31"
	resultsfile = "$(path)supergridruns1$runsuffix.jld2"
	# r = loadresults("regionset=Eurasia21, nuclearallowed=false, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]", resultsfile=resultsfile); sum(r.params[:demand])
	totaldemand = 1.8695380613113698e7	# (GWh/yr) 
	@load "$(path)supergridcosts1$runsuffix.jld2" resultslist allstatus
	res = resultslist
	carboncaps = Any[1000; 200; 100; 50; 20; 10; 5; 2; 1]	
	res0 = get(res,(true,1,:all,1),0)
	if res0 == 0
		res0 = get(res,(false,1,:all,1),0)
		res0 == 0 && error("No results for base case!")
	end
	function getresults(a,b,c,d)
		cost = get(res,(a,b,c,d),NaN)						# M€/year
		return cost > 1e7 ? NaN : cost/totaldemand*1000		# €/MWh
	end
	# resmat1 = [getresults(true,1,tm,cap/1000) for cap in carboncaps, tm in [:islands, :all]]
	resmat2 = [getresults(false,1,tm,cap/1000) for cap in carboncaps, tm in [:islands, :all]]
	# resmat3 = [getresults(true,2,tm,cap/1000) for cap in carboncaps, tm in [:islands, :all]]
	resmat4 = [getresults(false,2,tm,cap/1000) for cap in carboncaps, tm in [:islands, :all]]
	carboncaps[1] = "none"

	p = plot(string.(carboncaps), [resmat2 resmat4], color=[1 2 1 2], line=[:solid :solid :dash :dash])
	display(plot(p, size=(850,450), ylim=(0,60), 
					label=["C" "S" "C-Hland" "S-Hland"],
					line=3, tickfont=14, legendfont=14,
					titlefont=16, guidefont=14, xlabel="Global CO2 cap [g CO2/kWh]", ylabel="Average system cost [€/MWh]",
					left_margin=50px, gridlinewidth=1))
	# p1 = plot(string.(carboncaps), resmat1, title="Unlimited nuclear, default solar & wind area")
	p2 = plot(string.(carboncaps), resmat2, title="Low solar & wind area", label=["" ""])
	# p3 = plot(string.(carboncaps), resmat3, title="Unlimited nuclear, high solar & wind area")
	p4 = plot(string.(carboncaps), resmat4, title="High solar & wind area", label=[:islands :all])
	display(plot(p2, p4, layout=2, size=(1000,450), ylim=(0,60), line=3, tickfont=14, legendfont=14,
					titlefont=16, guidefont=14, xlabel="Global CO2 cap [g CO2/kWh]", ylabel="Average system cost [€/MWh]",
					left_margin=50px, gridlinewidth=1))
	# display(plot(p3, p4, layout=2, size=(1000,450), ylim=(0.9,2.5), label=[:none :islands :all], line=3, tickfont=16, legendfont=16,
	# 				titlefont=20, guidefont=16, xlabel="g CO2/kWh", ylabel="relative cost"))
end

function plot_supergridpaper_lines_transmission()
	path = "D:\\model runs\\"
	runsuffix = "_oct31"
	resultsfile = "$(path)supergridruns1$runsuffix.jld2"
	# r = loadresults("regionset=Eurasia21, nuclearallowed=false, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]", resultsfile=resultsfile); sum(r.params[:demand])
	totaldemand = 1.8695380613113698e7	# (GWh/yr) 
	@load "$(path)supergridcosts1$runsuffix.jld2" resultslist allstatus
	res = resultslist
	carboncaps = Any[1000; 200; 100; 50; 20; 10; 5; 2; 1]	
	res0 = get(res,(true,1,:all,1),0)
	if res0 == 0
		res0 = get(res,(false,1,:all,1),0)
		res0 == 0 && error("No results for base case!")
	end
	function getresults(a,b,c,d)
		cost = get(res,(a,b,c,d),NaN)						# M€/year
		return cost > 1e7 ? NaN : cost/totaldemand*1000		# €/MWh
	end
	# resmat1 = [getresults(true,1,tm,cap/1000) for cap in carboncaps, tm in [:islands, :all]]
	resmat2 = [getresults(false,1,tm,cap/1000) for cap in carboncaps, tm in [:none, :islands, :all]]
	# resmat3 = [getresults(true,2,tm,cap/1000) for cap in carboncaps, tm in [:islands, :all]]
	resmat4 = [getresults(false,2,tm,cap/1000) for cap in carboncaps, tm in [:none, :islands, :all]]
	carboncaps[1] = "none"

	p = plot(string.(carboncaps), [resmat2 resmat4], color=[3 1 2 3 1 2], line=[:solid :solid :solid :dash :dash :dash])
	display(plot(p, size=(850,450), ylim=(0,60), 
					label=["R" "C" "S" "R-Hland" "C-Hland" "S-Hland"],
					line=3, tickfont=14, legendfont=14,
					titlefont=16, guidefont=14, xlabel="Global CO2 cap [g CO2/kWh]", ylabel="Average system cost [€/MWh]",
					left_margin=50px, gridlinewidth=1))
end

# Figure 4 in the supergrid paper.
function plot_supergridpaper_bubbles()
	path = "D:\\model runs\\"
	runsuffix = "_oct31"
	@load "$(path)supergridcosts2$runsuffix.jld2" resultslist allstatus
	res = resultslist
	# showall(keys(res))
	rows = [3 3 3 2 2 2 1 1 1]
	cols = [3 2 1 3 2 1 3 2 1]
	r1 = [res[1,:islands,0.001,solar,battery]/res[1,:all,0.001,solar,battery]-1 for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
	r2 = [res[2,:islands,0.001,solar,battery]/res[2,:all,0.001,solar,battery]-1 for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
	bs = 0.4	# bubble size
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
function plot_supergridpaper_energymix()
	path = "D:\\model runs\\"
	runsuffix = "_oct31"
	resultsfile = "$(path)supergridruns1$runsuffix.jld2"
	scen = ["C", "S", "C_Hland", "S_Hland"]
	resultsnames = ["regionset=Eurasia21, transmissionallowed=islands, nuclearallowed=false, carboncap=0.001, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]",
					"regionset=Eurasia21, nuclearallowed=false, carboncap=0.001, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]",
					"regionset=Eurasia21, transmissionallowed=islands, nuclearallowed=false, carboncap=0.001, solarwindarea=2, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]",
					"regionset=Eurasia21, nuclearallowed=false, carboncap=0.001, solarwindarea=2, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]"]
	plot_energymix(scen, resultsnames, resultsfile)  #, deletetechs=[1,2,6,7,12])
end

function plot_supergridpaper_energymix_transmission()
	path = "D:\\model runs\\"
	runsuffix = "_oct31"
	resultsfile = "$(path)supergridruns1$runsuffix.jld2"
	scen = ["R", "C", "S", "R-Hland", "C-Hland", "S-Hland"]
	resultsnames = ["regionset=Eurasia21, transmissionallowed=none, nuclearallowed=false, carboncap=0.1, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]",
					"regionset=Eurasia21, transmissionallowed=islands, nuclearallowed=false, carboncap=0.1, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]",
					"regionset=Eurasia21, nuclearallowed=false, carboncap=0.1, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]",
					"regionset=Eurasia21, transmissionallowed=none, nuclearallowed=false, carboncap=0.1, solarwindarea=2, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]",
					"regionset=Eurasia21, transmissionallowed=islands, nuclearallowed=false, carboncap=0.1, solarwindarea=2, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]",
					"regionset=Eurasia21, nuclearallowed=false, carboncap=0.1, solarwindarea=2, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]"]
	plot_energymix(scen, resultsnames, resultsfile; size=(750,550))  #, deletetechs=[1,2,6,7,12])
end

function plot_supergridpaper_energymix_transmission2()
	path = "D:\\model runs\\"
	runsuffix = "_oct31"
	resultsfile = "$(path)supergridruns1$runsuffix.jld2"
	scen = ["C", "S", "R-Hland", "C-Hland", "S-Hland"]
	resultsnames = ["regionset=Eurasia21, transmissionallowed=islands, nuclearallowed=false, carboncap=0.05, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]",
					"regionset=Eurasia21, nuclearallowed=false, carboncap=0.05, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]",
					"regionset=Eurasia21, transmissionallowed=none, nuclearallowed=false, carboncap=0.05, solarwindarea=2, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]",
					"regionset=Eurasia21, transmissionallowed=islands, nuclearallowed=false, carboncap=0.05, solarwindarea=2, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]",
					"regionset=Eurasia21, nuclearallowed=false, carboncap=0.05, solarwindarea=2, islandindexes=UnitRange{Int64}[1:8, 9:15, 16:21]"]
	plot_energymix(scen, resultsnames, resultsfile; size=(750,550))  #, deletetechs=[1,2,6,7,12])
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

function plot_bubbles_v1()
	@load "iewruns2_1h.jld2" results allstatus
	res = results
	rows = [3 3 3 2 2 2 1 1 1]
	cols = [3 2 1 3 2 1 3 2 1]
	r = [(res[false,:islands,0.005,solar,battery]-res[false,:all,0.005,solar,battery])/res[false,:all,0.005,solar,battery] for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
	annotations = [(rows[i]-0.17*r[i]/0.06, cols[i], text("$(round(r[i]*100, digits=1))%", :right)) for i=1:9]
	s = scatter(rows, cols, markersize=reshape(r*500, (1,9)), annotations=annotations, xlim=(0.5,3.5), ylim=(0.5,3.5), legend=false,
					title="System cost diff: islands - all (no nuclear)", xlabel="battery cost", ylabel="solar PV cost",
					tickfont=12, guidefont=12)
	xticks!([1,2,3],["low","mid","high"])
	yticks!([1,2,3],["low","mid","high"])
	display(s)
end

function plot_bubbles_v2()
	@load "iewcosts2.jld2" resultslist allstatus
	res = resultslist
	rows = [3 3 3 2 2 2 1 1 1]
	cols = [3 2 1 3 2 1 3 2 1]
	r1 = [(res[1,:islands,0.001,solar,battery]-res[1,:all,0.001,solar,battery])/res[1,:all,0.001,solar,battery] for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
	r2 = [(res[4,:islands,0.001,solar,battery]-res[4,:all,0.001,solar,battery])/res[4,:all,0.001,solar,battery] for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
	annotations1 = [(rows[i]-0.17*r1[i]/0.06, cols[i], text("$(round(r1[i]*100, digits=1))%", :right)) for i=1:9]
	annotations2 = [(rows[i]-0.17*r2[i]/0.06, cols[i], text("$(round(r2[i]*100, digits=1))%", :right)) for i=1:9]
	s1 = scatter(rows, cols, markersize=reshape(r1*500, (1,9)), annotations=annotations1, xlim=(0.5,3.5), ylim=(0.5,3.5), legend=false,
					title="System cost diff: islands - all (default solar/wind area)", xlabel="battery cost", ylabel="solar PV cost",
					tickfont=12, guidefont=12)
	xticks!([1,2,3],["low","mid","high"])
	yticks!([1,2,3],["low","mid","high"])
	s2 = scatter(rows, cols, markersize=reshape(r2*500, (1,9)), annotations=annotations2, xlim=(0.5,3.5), ylim=(0.5,3.5), legend=false,
					title="System cost diff: islands - all (high solar/wind area)", xlabel="battery cost", ylabel="solar PV cost",
					tickfont=12, guidefont=12)
	xticks!([1,2,3],["low","mid","high"])
	yticks!([1,2,3],["low","mid","high"])
	display(plot(s1, s2, layout=2, size=(1350,650)))
end

function plot_bubbles_v2_abs()
	totaldemand = 1.8695380613113698e7	# (GWh/yr) r = loadresults("nuclearallowed=false", resultsfile="iewruns1.jld2");  sum(r.params[:demand])
	@load "iewcosts2.jld2" resultslist allstatus
	res = resultslist
	rows = [3 3 3 2 2 2 1 1 1]
	cols = [3 2 1 3 2 1 3 2 1]
	r1 = [(res[1,:islands,0.001,solar,battery]-res[1,:all,0.001,solar,battery])/totaldemand*1000 for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
	r2 = [(res[4,:islands,0.001,solar,battery]-res[4,:all,0.001,solar,battery])/totaldemand*1000 for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
	annotations1 = [(rows[i]-0.06*r1[i], cols[i], text("$(round(r1[i], digits=1))", :right)) for i=1:9]
	annotations2 = [(rows[i]-0.06*r2[i], cols[i], text("$(round(r2[i], digits=1))", :right)) for i=1:9]
	s1 = scatter(rows, cols, markersize=reshape(r1*10, (1,9)), annotations=annotations1, xlim=(0.5,3.5), ylim=(0.5,3.5), legend=false,
					title="System cost diff [€/MWh]: islands - all (default solar/wind area)", xlabel="battery cost", ylabel="solar PV cost",
					tickfont=12, guidefont=12)
	xticks!([1,2,3],["low","mid","high"])
	yticks!([1,2,3],["low","mid","high"])
	s2 = scatter(rows, cols, markersize=reshape(r2*10, (1,9)), annotations=annotations2, xlim=(0.5,3.5), ylim=(0.5,3.5), legend=false,
					title="System cost diff [€/MWh]: islands - all (high solar/wind area)", xlabel="battery cost", ylabel="solar PV cost",
					tickfont=12, guidefont=12)
	xticks!([1,2,3],["low","mid","high"])
	yticks!([1,2,3],["low","mid","high"])
	display(plot(s1, s2, layout=2, size=(1350,650)))
end

function plot_biolines_v1()
	@load "iewruns1_1h.jld2" results allstatus
	res0 = results[true,:all,1]
	@load "iewruns3_1h.jld2" results allstatus
	res = results
	carboncaps = [5; 0]
	allbio = [0, 0.025, 0.05, 0.075, 0.1, 0.15, 0.2, 0.3]
	res_islands = [res[bio,:islands,cap/1000]/res0 for cap in carboncaps, bio in allbio]
	res_all = [res[bio,:all,cap/1000]/res0 for cap in carboncaps, bio in allbio]
	# p1 = plot(string.(carboncaps), res_islands, title="islands")
	# p2 = plot(string.(carboncaps), res_all, title="all")
	# display(plot(p1, p2, layout=2, size=(1850,950), ylim=(0.9,2.5), label=biolabels, line=3, tickfont=16, legendfont=16,
	# 				titlefont=20, guidefont=16, xlabel="g CO2/kWh", ylabel="relative cost"))
	biolabels_islands = ["bio=$b, islands" for i in 1:1, b in allbio]
	biolabels_all = ["bio=$b, all" for i in 1:1, b in allbio]
	p = plot(string.(carboncaps), res_islands, size=(650,950), ylim=(0.9,2.5), label=biolabels_islands, line=(3,:dash), tickfont=16, legendfont=16,
					color=reshape(1:8,(1,8)), titlefont=20, guidefont=16, xlabel="g CO2/kWh", ylabel="relative cost")
	plot!(string.(carboncaps), res_all, color=reshape(1:8,(1,8)), label=biolabels_all, line=3)
	display(p)
end

# function plotiew1_v2(res)
# 	carboncaps = [1; 0.2; 0.1; 0.05; 0.02; 0.01; 0.005; 0.002; 0.001; 0]	
# 	res0 = res[true,:all,1]
# 	resmat1 = [res[true,tm,cap]/res0 for cap in carboncaps, tm in [:none, :islands, :all]]
# 	resmat2 = [res[false,tm,cap]/res0 for cap in carboncaps, tm in [:none, :islands, :all]]
# 	plot(string.(carboncaps), [resmat2 resmat1], size=(1850,950), label=[:none_nonuke :islands_nonuke :all_nonuke :none :islands :all],
# 		line=3, tickfont=16, legendfont=16, titlefont=20, guidefont=16, xlabel="g CO2/kWh", ylabel="relative cost")
# end

# function plotiew2_old(res)
# 	row = [1 1 1; 2 2 2; 3 3 3]
# 	col = [1 2 3; 1 2 3; 1 2 3]
# 	# row = [solar for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
# 	# col = [battery for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
# 	resmat1 = [(res[true,:islands,0.005,solar,battery]-res[true,:all,0.005,solar,battery])/res[true,:all,0.005,:low,:low] for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
# 	resmat2 = [(res[false,:islands,0.005,solar,battery]-res[false,:all,0.005,solar,battery])/res[true,:all,0.005,:low,:low] for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
# 	display(resmat1)
# 	println()
# 	display(resmat2)
# 	display(scatter(row, col, markersize=resmat1*100, title="nuclear"))
# 	display(scatter(row, col, markersize=resmat2*100, title="no nuclear"))
# end



#=
for nuc in [false, true], tm in [:none, :islands, :all], cap in [1, 0.2, 0.1, 0.05, 0.02, 0.01, 0.005, 0]
   s = allstatus[nuc,tm,cap]
   s != :Optimal && println("$nuc, $tm, $cap: $s")
end

results[false,:all,0.1] = 0.5*(8.5223549e+05 + 8.5223282e+05)
results[true,:none,0.01] = 0.5*(9.5207609e+05 + 9.5207205e+05)
results[true,:none,0.005] = 0.5*(9.6381845e+05 + 9.6381386e+05)
results[true,:islands,0.01] = 0.5*(9.2467909e+05 + 9.2467558e+05)

results[false,:islands,0.005,:high,:low] = 0.5*(1.1262351e+06 + 1.1262346e+06)
results[false,:all,0.005,:mid,:high] = 0.5*(1.1611178e+06 + 1.1611177e+06)
results[false,:all,0.005,:mid,:mid] = 0.5*(1.0995099e+06 + 1.0995086e+06)
results[false,:all,0.005,:low,:high] = 0.5*(1.0677177e+06 + 1.0677151e+06)

=#