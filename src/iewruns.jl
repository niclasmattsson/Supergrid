using Plots, JLD2, FileIO

plotly()

function IEWruns(hourinterval)
	results = Dict()
	for nuc in [false, true]
		for tm in [:none, :islands, :all]
			for cap in [1, 0.2, 0.1, 0.05, 0.02, 0.01, 0.005, 0]
				println("\n\n\nNew run: nuclear=$nuc, transmission=$tm, cap=$cap.")
				model = buildmodel(sampleinterval=hourinterval, carboncap=cap, maxbiocapacity=0.05, nuclearallowed=nuc, transmissionallowed=tm)
				println("\nSolving model...")
				status = solve(model.modelname)
				println("\nSolve status: $status")
				results[nuc,tm,cap] = (status == :Optimal) ? sum(getvalue(model.vars.Systemcost)) : NaN
			end
		end
	end
	@save "iewruns1_$(hourinterval)h.jld2" results
	results
end

function IEWruns2(hourinterval)
	results = Dict()
	for nuc in [false]
		for tm in [:islands, :all]
			for cap in [0.005]
				options, hourinfo, sets, params = buildsetsparams(sampleinterval=hourinterval, carboncap=cap, maxbiocapacity=0.05, nuclearallowed=nuc, transmissionallowed=tm)
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
						results[nuc,tm,cap,solar,battery] = (status == :Optimal) ? sum(getvalue(model.vars.Systemcost)) : NaN
					end
				end
			end
		end
	end
	@save "iewruns2_$(hourinterval)h.jld2" results
	results
end

# using JLD2, Plots; @load "iewruns1_3h.jld2" res; plotly()
function plotiew(res)
	carboncaps = [1000; 200; 100; 50; 20; 10; 0]	
	res0 = res[true,:all,1]
	resmat1 = [res[true,tm,cap/1000]/res0 for cap in carboncaps, tm in [:none, :islands, :all]]
	resmat2 = [res[false,tm,cap/1000]/res0 for cap in carboncaps, tm in [:none, :islands, :all]]
	p1 = plot(string.(carboncaps), resmat1, title="nuclear")
	p2 = plot(string.(carboncaps), resmat2, title="no nuclear")
	plot(p1, p2, layout=2, size=(1850,950), ylim=(0.9,2.5), label=[:none :islands :all], line=3, tickfont=16, legendfont=16,
					titlefont=20, guidefont=16, xlabel="g CO2/kWh", ylabel="relative cost")
end

function plotiew_v2(res)
	carboncaps = [1; 0.2; 0.1; 0.05; 0.02; 0.01; 0]	
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
	resmat1 = [(res[true,:islands,0.01,solar,battery]-res[true,:all,0.01,solar,battery])/res[true,:all,0.01,:low,:low] for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
	resmat2 = [(res[false,:islands,0.01,solar,battery]-res[false,:all,0.01,solar,battery])/res[true,:all,0.01,:low,:low] for solar in [:high, :mid, :low], battery in [:high, :mid, :low]]
	display(resmat1)
	println()
	display(resmat2)
	display(scatter(row, col, markersize=resmat1*100, title="nuclear"))
	display(scatter(row, col, markersize=resmat2*100, title="no nuclear"))
end