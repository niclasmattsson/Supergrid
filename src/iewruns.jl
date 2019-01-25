using Plots, JLD2, FileIO, Plots.PlotMeasures

plotly()

function IEWruns1(hourinterval)
	resultslist = Dict()
	allstatus = Dict()
	runcount = 0
	for nuc in [false]
		for solarwind in [1, 4]
			for tm in [:none, :islands, :all]
				for cap in [1, 0.2, 0.1, 0.05, 0.02, 0.01, 0.005, 0.002, 0.001, 0]
					runcount += 1
					runcount in [1] && continue
					println("\n\n\nNew run: nuclear=$nuc, solarwind=$solarwind, transmission=$tm, cap=$cap.")
					model = buildmodel(hours=hourinterval, carboncap=cap, maxbiocapacity=0.05, 
										nuclearallowed=nuc, transmissionallowed=tm, solarwindarea=solarwind)
					println("\nSolving model...")
					status = solve(model.modelname)
					println("\nSolve status: $status")
					resultslist[nuc,solarwind,tm,cap] = sum(getvalue(model.vars.Systemcost))
					allstatus[nuc,solarwind,tm,cap] = status
					@save "iewcosts1.jld2" resultslist allstatus
					println("\nReading results...")
					results = readresults(model, status)
					name = autorunname(model.options)
					println("\nSaving results to disk...")
					saveresults(results, name, filename="iewruns1.jld2")
				end
			end
		end
	end
	resultslist, allstatus
end

function IEWruns2(hourinterval)
	results = Dict()
	allstatus = Dict()
	for nuc in [false]
		for tm in [:islands, :all]
			for cap in [0.005]
				options, hourinfo, sets, params = buildsetsparams(hours=hourinterval, carboncap=cap, maxbiocapacity=0.05,
										nuclearallowed=nuc, transmissionallowed=tm)
				pvcost = params.investcost[:pv,:a1]
				pvroofcost = params.investcost[:pvroof,:a1]
				batterycost = params.investcost[:battery,:_]
				for solar in [:high, :mid, :low]
					for battery in [:high, :mid, :low]
						println("\n\n\nNew run: nuclear=$nuc, transmission=$tm, cap=$cap, solar=$solar, battery=$battery.")
						for c in sets.CLASS[:pv]
							if solar == :high
								params.investcost[:pv,c] = pvcost * 1.5
								params.investcost[:pvroof,c] = pvroofcost + pvcost * 0.5
							elseif solar == :mid
								params.investcost[:pv,c] = pvcost
								params.investcost[:pvroof,c] = pvroofcost
							elseif solar == :low
								params.investcost[:pv,c] = pvcost * 0.5
								params.investcost[:pvroof,c] = pvroofcost - pvcost * 0.5
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
						results[nuc,tm,cap,solar,battery] = status == :Optimal ? sum(getvalue(model.vars.Systemcost)) : NaN
						allstatus[nuc,tm,cap,solar,battery] = status
						@save "iewruns2_$(hourinterval)h.jld2" results allstatus
					end
				end
			end
		end
	end
	results, allstatus
end

function IEWruns3(hourinterval)
	results = Dict()
	allstatus = Dict()
	for bio in [0, 0.025, 0.05, 0.075, 0.1, 0.15, 0.2, 0.3]
		for tm in [:islands, :all]
			for cap in [0.005, 0]
				println("\n\n\nNew run: bio=$bio, transmission=$tm, cap=$cap.")
				model = buildmodel(hours=hourinterval, carboncap=cap, maxbiocapacity=bio, 
									nuclearallowed=false, transmissionallowed=tm)
				println("\nSolving model...")
				status = solve(model.modelname)
				println("\nSolve status: $status")
				results[bio,tm,cap] = sum(getvalue(model.vars.Systemcost))
				allstatus[bio,tm,cap] = status
				@save "iewruns3_$(hourinterval)h.jld2" results allstatus
			end
		end
	end
	results, allstatus
end

function mergeresults()
	@load "iewcosts1_0.jld2" resultslist allstatus
	res0, st0 = resultslist, allstatus
	@load "iewcosts1.jld2" resultslist allstatus
	resultslist[false, 1, :none, 1.0] = res0[false, 1, :none, 1.0] 
	allstatus[false, 1, :none, 1.0] = st0[false, 1, :none, 1.0] 
	@save "iewcosts1.jld2" resultslist allstatus
end

function plotiew_lines_v2()
	@load "iewcosts1.jld2" resultslist allstatus
	res = resultslist
	carboncaps = [1000; 200; 100; 50; 20; 10; 5; 2; 1; 0]	
	res0 = get(res,(true,1,:all,1),0)
	if res0 == 0
		res0 = get(res,(false,1,:all,1),0)
		res0 == 0 && error("No results for base case!")
	end
	function getresults(a,b,c,d)
		out = get(res,(a,b,c,d),NaN)
		return out > 1e7 ? NaN : out/res0
	end
	resmat1 = [getresults(true,1,tm,cap/1000) for cap in carboncaps, tm in [:none, :islands, :all]]
	resmat2 = [getresults(false,1,tm,cap/1000) for cap in carboncaps, tm in [:none, :islands, :all]]
	resmat3 = [getresults(true,4,tm,cap/1000) for cap in carboncaps, tm in [:none, :islands, :all]]
	resmat4 = [getresults(false,4,tm,cap/1000) for cap in carboncaps, tm in [:none, :islands, :all]]
	display(resmat2)
	p1 = plot(string.(carboncaps), resmat1, title="nuclear, default solar & wind area")
	p2 = plot(string.(carboncaps), resmat2, title="no nuclear, default solar & wind area")
	p3 = plot(string.(carboncaps), resmat3, title="nuclear, high solar & wind area")
	p4 = plot(string.(carboncaps), resmat4, title="no nuclear, high solar & wind area")
	display(plot(p2, p4, layout=2, size=(1850,950), ylim=(0.9,2.5), label=[:none :islands :all], line=3, tickfont=16, legendfont=16,
					titlefont=20, guidefont=16, xlabel="g CO2/kWh", ylabel="relative cost"))
	# display(plot(p3, p4, layout=2, size=(1850,950), ylim=(0.9,2.5), label=[:none :islands :all], line=3, tickfont=16, legendfont=16,
	# 				titlefont=20, guidefont=16, xlabel="g CO2/kWh", ylabel="relative cost"))
end

# using JLD2, Plots; @load "iewruns1_1h.jld2" results allstatus; plotly()
function plotiew_lines_v1()
	@load "iewruns1_1h.jld2" results allstatus
	res = results
	carboncaps = [1000; 200; 100; 50; 20; 10; 5; 2; 1; 0]	
	res0 = res[true,:all,1]
	resmat1 = [res[true,tm,cap/1000]/res0 for cap in carboncaps, tm in [:none, :islands, :all]]
	resmat2 = [res[false,tm,cap/1000]/res0 for cap in carboncaps, tm in [:none, :islands, :all]]
	p1 = plot(string.(carboncaps), resmat1, title="nuclear")
	p2 = plot(string.(carboncaps), resmat2, title="no nuclear")
	display(plot(p1, p2, layout=2, size=(1850,950), ylim=(0.9,2.5), label=[:none :islands :all], line=3, tickfont=16, legendfont=16,
					titlefont=20, guidefont=16, xlabel="g CO2/kWh", ylabel="relative cost"))
end

function plotiew_bubbles_v1()
	@load "iewruns2_1h.jld2" results allstatus
	res = results
	rows = [3 3 3 2 2 2 1 1 1]
	cols = [3 2 1 3 2 1 3 2 1]
	r = [(res[false,:islands,0.005,solar,battery]-res[false,:all,0.005,solar,battery])/res[false,:all,0.005,:low,:low] for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
	annotations = [(rows[i]-0.17*r[i]/0.06, cols[i], text("$(round(r[i]*100, digits=1))%", :right)) for i=1:9]
	s = scatter(rows, cols, markersize=reshape(r*500, (1,9)), annotations=annotations, xlim=(0.5,3.5), ylim=(0.5,3.5), legend=false,
					title="System cost diff: islands - all (no nuclear)", xlabel="battery cost", ylabel="solar PV cost",
					tickfont=12, guidefont=12)
	xticks!([1,2,3],["low","mid","high"])
	yticks!([1,2,3],["low","mid","high"])
	display(s)
end

function plotiew_biolines_v1()
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