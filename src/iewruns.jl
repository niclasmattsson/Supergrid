using Plots, JLD2, FileIO

plotly()

function IEWruns(hourinterval)
	results = Dict()
	allstatus = Dict()
	for nuc in [false, true]
		for tm in [:none, :islands, :all]
			for cap in [1, 0.2, 0.1, 0.05, 0.02, 0.01, 0.005, 0.002, 0.001, 0]
				println("\n\n\nNew run: nuclear=$nuc, transmission=$tm, cap=$cap.")
				model = buildmodel(sampleinterval=hourinterval, carboncap=cap, maxbiocapacity=0.05, 
									nuclearallowed=nuc, transmissionallowed=tm, threads=3)
				println("\nSolving model...")
				status = solve(model.modelname)
				println("\nSolve status: $status")
				results[nuc,tm,cap] = sum(getvalue(model.vars.Systemcost))
				allstatus[nuc,tm,cap] = status
				@save "iewruns1_$(hourinterval)h.jld2" results allstatus
			end
		end
	end
	results, allstatus
end

function IEWruns2(hourinterval)
	results = Dict()
	allstatus = Dict()
	for nuc in [false]
		for tm in [:islands, :all]
			for cap in [0.005]
				options, hourinfo, sets, params = buildsetsparams(sampleinterval=hourinterval, carboncap=cap, maxbiocapacity=0.05,
										nuclearallowed=nuc, transmissionallowed=tm, threads=3)
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

# using JLD2, Plots; @load "iewruns1_1h.jld2" results allstatus; plotly()
function plotiew()
	@load "iewruns1_1h.jld2" results allstatus
	plotiew1(results)
	@load "iewruns2_1h.jld2" results allstatus
	plotiew2_v2(results)
end

function plotiew1(res)
	carboncaps = [1000; 200; 100; 50; 20; 10; 5; 2; 1; 0]	
	res0 = res[true,:all,1]
	resmat1 = [res[true,tm,cap/1000]/res0 for cap in carboncaps, tm in [:none, :islands, :all]]
	resmat2 = [res[false,tm,cap/1000]/res0 for cap in carboncaps, tm in [:none, :islands, :all]]
	p1 = plot(string.(carboncaps), resmat1, title="nuclear")
	p2 = plot(string.(carboncaps), resmat2, title="no nuclear")
	display(plot(p1, p2, layout=2, size=(1850,950), ylim=(0.9,2.5), label=[:none :islands :all], line=3, tickfont=16, legendfont=16,
					titlefont=20, guidefont=16, xlabel="g CO2/kWh", ylabel="relative cost"))
end

function plotiew1_v2(res)
	carboncaps = [1; 0.2; 0.1; 0.05; 0.02; 0.01; 0.005; 0.002; 0.001; 0]	
	res0 = res[true,:all,1]
	resmat1 = [res[true,tm,cap]/res0 for cap in carboncaps, tm in [:none, :islands, :all]]
	resmat2 = [res[false,tm,cap]/res0 for cap in carboncaps, tm in [:none, :islands, :all]]
	plot(string.(carboncaps), [resmat2 resmat1], size=(1850,950), label=[:none_nonuke :islands_nonuke :all_nonuke :none :islands :all],
		line=3, tickfont=16, legendfont=16, titlefont=20, guidefont=16, xlabel="g CO2/kWh", ylabel="relative cost")
end

function plotiew2(res)
	row = [1 1 1; 2 2 2; 3 3 3]
	col = [1 2 3; 1 2 3; 1 2 3]
	# row = [solar for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
	# col = [battery for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
	resmat1 = [(res[true,:islands,0.005,solar,battery]-res[true,:all,0.005,solar,battery])/res[true,:all,0.005,:low,:low] for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
	resmat2 = [(res[false,:islands,0.005,solar,battery]-res[false,:all,0.005,solar,battery])/res[true,:all,0.005,:low,:low] for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
	display(resmat1)
	println()
	display(resmat2)
	display(scatter(row, col, markersize=resmat1*100, title="nuclear"))
	display(scatter(row, col, markersize=resmat2*100, title="no nuclear"))
end

function plotiew2_v2(res)
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