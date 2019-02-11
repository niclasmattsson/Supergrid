using NamedArrays, StatsPlots, JLD2

sumdimdrop(x::AbstractArray; dims) = dropdims(sum(x, dims=dims), dims=dims)

# Convert a JuMPArray to an AxisArray. Uses current JuMPArray internals, will need a rewrite in the next JuMP version.
AxisArrays.AxisArray(ja::JuMP.JuMPArray) = AxisArray(ja.innerArray, ja.indexsets...)

# Convert a JuMPDict to an AxisArray. Uses current JuMPDict internals, will need a rewrite in the next JuMP version.
# function AxisArrays.AxisArray(jd::JuMP.JuMPDict)
# 	d = jd.tupledict
# 	k = keys(d)
# 	ndims = length(iterate(k)[1])
# 	sets = [unique(getindex.(k,dim)) for dim=1:ndims]
# 	a = AxisArray(zeros(length.(sets)...), sets...)
# 	for (key, value) in d
# 		a[key...] = value
# 	end
# 	return a
# end

# Convert a JuMPDict to a Dict. Uses current JuMPDict internals, will need a rewrite in the next JuMP version.
getdict(jd::JuMP.JuMPDict) = jd.tupledict

function readresults(model::ModelInfo, status::Symbol)
	@unpack REGION, TECH, CLASS, HOUR, techtype, STORAGECLASS = model.sets
	@unpack Systemcost, CO2emissions, FuelUse, Electricity, Charging, StorageLevel, Transmission, TransmissionCapacity, Capacity = model.vars
	@unpack demand, classlimits, hydrocapacity = model.params
	storagetechs = [k for k in TECH if techtype[k] == :storage]

	params = Dict(:demand => demand, :classlimits => classlimits, :hydrocapacity => hydrocapacity)

	cost = AxisArray(getvalue(Systemcost))
	emis = AxisArray(getvalue(CO2emissions))
	fuel = AxisArray(getvalue(FuelUse))
	# getting Electricity for all set combos is slowest, so let's optimize storage format and use faster internal function call 
	elec = Dict((k,c) => [JuMP._getValue(Electricity[r,k,c,h]) for h in HOUR, r in REGION] for k in TECH for c in CLASS[k]);
	charge = getdict(getvalue(Charging))
	# oops, StorageLevel is also slow
	storage = Dict((k,c) => [JuMP._getValue(StorageLevel[r,k,c,h]) for h in HOUR, r in REGION] for k in storagetechs for c in STORAGECLASS[k]);
	transmission = AxisArray(getvalue(Transmission))
	transmissioncapac = AxisArray(getvalue(TransmissionCapacity))
	capac = getdict(getvalue(Capacity))

	return Results(status, model.options, model.hourinfo, model.sets, params, cost, emis, fuel, elec, charge, storage, transmission, transmissioncapac, capac)
end

function saveresults(results::Results, runname; filename="results.jld2", group="", compress=true)
	if !isempty(group) && group[end] != '/'
		group *= "/"
	end
	runname = "$group$runname"
	jldopen(filename, "a+", compress=compress) do file
		if haskey(file, runname)
			@warn "The run $runname already exists in $filename (new run not saved to disk). "
		else
			file[runname] = results
		end
	end
	return nothing
end

function listresults(; filename="results.jld2", group="")
	if !isempty(group) && group[end] != '/'
		group *= "/"
	end
	jldopen(filename, "r") do file
		display(file)
	end
	return nothing
end

function loadresults(; filename="results.jld2", group="", loadoptions...)
	options = merge(defaultoptions(), loadoptions)
	loadresults(autorunname(options); filename=filename, group=group)
end

function loadresults(runname::String; filename="results.jld2", group="")
	if !isempty(group) && group[end] != '/'
		group *= "/"
	end
	runname = "$group$runname"
	results = nothing
	jldopen(filename, "r") do file
		if haskey(file, runname)
			results = file[runname]
		else
			println("\nThe run $runname does not exist in $filename.")
		end
	end
	return results
end

function showresults(results::Results)
	@unpack REGION, FUEL, TECH, CLASS, HOUR, techtype, STORAGECLASS = results.sets
	@unpack demand, classlimits, hydrocapacity = results.params
	@unpack CO2emissions, FuelUse, Electricity, Transmission, Capacity, TransmissionCapacity, Charging, StorageLevel, Systemcost = results
	
	hoursperperiod = results.hourinfo.hoursperperiod

	capacmat = [sum(Capacity[r,k,c] for c in CLASS[k]) for k in TECH, r in REGION]
	capac = NamedArray([capacmat sum(capacmat, dims=2)], (TECH, [REGION; :TOTAL]))
	elec = zeros(length(HOUR), length(TECH), length(REGION))
	for (i,k) in enumerate(TECH)
		elec[:,i,:] = sum(Electricity[k,c] for c in CLASS[k])
	end
	annualelec = NamedArray([sumdimdrop(elec,dims=1) sumdimdrop(elec, dims=(1,3))], (TECH, [REGION; :TOTAL]), (:TECH, :REGION))
	charge = [Charging[r,:battery,h] for h in HOUR, r in REGION]
	storagetechs = [k for k in TECH if techtype[k] == :storage]
	storage = zeros(length(HOUR), length(storagetechs), length(REGION))
	for (i,k) in enumerate(storagetechs)
		storage[:,i,:] = sum(StorageLevel[k,c] for c in STORAGECLASS[k])
	end
	existingstoragelevel = NamedArray(storage, (collect(HOUR), storagetechs, REGION), (:HOUR, :TECH, :REGION))
	tcapac = NamedArray([TransmissionCapacity[r1,r2] for r1 in REGION, r2 in REGION], (REGION,REGION))

	# @unpack ElecDemand = model.constraints
	# prices = [getdual(ElecDemand[r,h]) for r in REGION, h in HOUR]
	# prices = NamedArray([getdual(ElecDemand[r,h]) for r in REGION, h in HOUR], (REGION, collect(HOUR)))		# €/kWh

	plotly()

	palette = [
		#RGB([68,131,208]/255...),	#hydroRoR
		RGB([216,137,255]/255...),	#nuclear			or RGBA{Float64}(0.76444,0.444112,0.824298,1.0)
		RGB([119,112,71]/255...),	#coal
		#RGB([164,155,104]/255...),	#coal CCS
		RGB([199,218,241]/255...),	#wind
		RGB([149,179,215]/255...),	#wind offshore
		RGB([255,255,64]/255...),	#solarPV
		RGB([240,224,0]/255...),	#PVrooftop
		RGB([214,64,64]/255...),	#solarCSP
		RGB([255,192,0]/255...),	#CCGT
		RGB([99,172,70]/255...),	#bioCCGT
		RGB([100,136,209]/255...),	#hydro
		RGB([144,213,93]/255...),	#bioGT
		RGB([148,138,84]/255...),	#gasGT
		RGB([157,87,205]/255...),	#battery
	]

	displaytechs = [:nuclear, :coal, :wind, :offwind, :pv, :pvroof, :csp, :gasCCGT, :bioCCGT, :hydro, :bioGT, :gasGT, :battery]
	techlabels = [k for r=1:1, k in displaytechs]
	displayorder = [i for (i,k) in enumerate(TECH), d in displaytechs if d == k]

	function chart(country::Symbol, plotstoragetech=:none)
		if country == :BARS
			regcost = Systemcost ./ vec(sum(annualelec, dims=1)[1:end-1]) * 1000
			totcost = sum(Systemcost) / sum(annualelec[:,:TOTAL]) * 1000
			lcoe = NamedArray(collect([regcost; totcost]'), (["system cost (€/MWh)"], [REGION; :TOTAL]))
			display(lcoe)

			groupedbar(String.(REGION),collect(annualelec[displayorder,1:end-1]'/1000), labels=techlabels, bar_position = :stack, size=(1850,950), line=0, tickfont=14, legendfont=14, color_palette=palette)
			lr = length(REGION)
			xpos = (1:lr)' .- 0.5
			display(plot!([xpos; xpos], [zeros(lr)'; sum(demand,dims=2)'*hoursperperiod/1000], line=3, color=:black, labels=permutedims(repeat([""],lr))))
			if lr == 21
				totelec = [sumdimdrop(annualelec[:,1:8],dims=2) sumdimdrop(annualelec[:,9:15],dims=2) sumdimdrop(annualelec[:,16:21],dims=2) annualelec[:,:TOTAL]]
				groupedbar(["EU","CAS","China","TOTAL"],collect(totelec[displayorder,:]'/1e6), labels=techlabels, bar_position = :stack, size=(500,950), line=0, tickfont=14, legendfont=14, color_palette=palette)
				xpos = (1:4)' .- 0.5
				totdemand = [sum(demand[1:8,:]) sum(demand[9:15,:]) sum(demand[16:21,:]) sum(demand)]
				display(plot!([xpos; xpos], [zeros(4)'; totdemand*hoursperperiod/1e6], line=3, color=:black, labels=permutedims(repeat([""],4))))
			else
				groupedbar(["TOTAL"],collect(annualelec[displayorder,:TOTAL]')/1e6, labels=techlabels, bar_position = :stack, size=(500,950), line=0, tickfont=14, legendfont=14, color_palette=palette)
				xpos = (1:1)' .- 0.5
				totdemand = [sum(demand)]
				display(plot!([xpos; xpos], [zeros(1)'; totdemand*hoursperperiod/1e6], line=3, color=:black, labels=permutedims(repeat([""],1))))
			end
			return nothing
		end

		if country == :TOTAL || country == :TOT || country == :total || country == :tot
			regs = 1:length(REGION)
		elseif country == :EU || country == :eu
			regs = 1:8
		elseif country == :ASIA || country == :asia
			regs = 9:15
		elseif country == :CHINA || country == :china || country == :CH || country == :ch
			regs = 16:21
		else
			countryindex = findfirst(REGION .== country)
			countryindex == nothing && error("Region $country not in $REGION.")
			regs = [countryindex]
		end

		regelec = sumdimdrop(elec[:,:,regs], dims=3)[:,displayorder] / hoursperperiod
		regcharge = sumdimdrop(charge[:,regs], dims=2) / hoursperperiod
		regdemand = sumdimdrop(demand[regs,:], dims=1)

		composite = plot(layout = 6, size=(1850,950), legend=false)
		for (i,k) in enumerate([:wind, :offwind, :hydro, :pv, :pvroof, :csp])
			colors = [palette[findfirst(displaytechs .== k)]; RGB(0.9,0.9,0.9)]
			used = [sum(Capacity[r,k,c] for r in REGION[regs]) for c in CLASS[k]]
			lims = [sum(k == :hydro ? hydrocapacity[r,c] : classlimits[r,k,c] for r in REGION[regs]) for c in CLASS[k]]
			groupedbar!(String.(CLASS[k]), [used lims-used], subplot=i, bar_position = :stack, line=0, color_palette=colors)
		end
		display(composite)

		if plotstoragetech != :none
			regstorage = sumdimdrop(existingstoragelevel[:,[plotstoragetech],regs], dims=3)
			p = plot(regstorage, size=(1850,950), tickfont=16, legendfont=16, label="storage level (TWh)")
			if plotstoragetech == :battery
				plot!(regcharge/1000, label="charge (TWh/h)")
				batteryelec = sumdimdrop([Electricity[:battery,:_][r,h] for r in REGION, h in HOUR][regs,:], dims=1) / hoursperperiod
				plot!(batteryelec/1000, label="discharge (TWh/h)")
			end
			display(p)
		end

		# level = [getvalue(StorageLevel[r,:battery,:_,h])*100 for h in HOUR, r in REGION]
		# reglevel = sumdimdrop(level[:,regs], dims=2)
		# display(plot(HOUR,[regcharge regelec[:,12] reglevel],size=(1850,950)))

		stackedarea(HOUR, regelec, labels=techlabels, size=(1850,950), line=0, tickfont=16, legendfont=16, color_palette=palette)
		plot!(HOUR, -regcharge)
		display(plot!(HOUR, regdemand, c=:black))
		nothing
	end

	# chart(:NOR)
	
	# if true	# plot hydro storage & shadow prices
	# 	plot(elec[:,:hydro,:NOR]/hoursperperiod/1000, size=(1850,950), tickfont=16, legendfont=16)
	# 	plot!(sum(elec[:,:wind,:],2)/hoursperperiod/1000)
	# 	display(plot!(vec(mean(prices,1))))
	# end

	return annualelec, capac, tcapac, chart
end


#=
default colors
get_color_palette(:auto, default(:bgcolor), 13)

 RGBA{Float64}(0.0,0.605603,0.97868,1.0)
 RGBA{Float64}(0.888874,0.435649,0.278123,1.0)
 RGBA{Float64}(0.242224,0.643275,0.304449,1.0)
 RGBA{Float64}(0.76444,0.444112,0.824298,1.0)
 RGBA{Float64}(0.675544,0.555662,0.0942343,1.0)
 RGBA{Float64}(4.82118e-7,0.665759,0.680997,1.0)
 RGBA{Float64}(0.930767,0.367477,0.57577,1.0)
 RGBA{Float64}(0.776982,0.509743,0.146425,1.0)
 RGBA{Float64}(3.80773e-7,0.664268,0.552951,1.0)
 RGBA{Float64}(0.558465,0.593485,0.117481,1.0)
 RGBA{Float64}(5.94762e-7,0.660879,0.798179,1.0)
 RGBA{Float64}(0.609671,0.499185,0.911781,1.0)
 RGBA{Float64}(0.380002,0.551053,0.966506,1.0)



function test()
_Systemcost = AxisArray(getvalue(m.vars.Systemcost))
_CO2emissions = AxisArray(getvalue(m.vars.CO2emissions))
_FuelUse = AxisArray(getvalue(m.vars.FuelUse))
_Electricity = Supergrid.getdict(getvalue(m.vars.Electricity))
_Charging = Supergrid.getdict(getvalue(m.vars.Charging))
_StorageLevel = Supergrid.getdict(getvalue(m.vars.StorageLevel))
_Transmission = AxisArray(getvalue(m.vars.Transmission))
_TransmissionCapacity = AxisArray(getvalue(m.vars.TransmissionCapacity))
_Capacity = Supergrid.getdict(getvalue(m.vars.Capacity))
end

@time elec = [sum(getvalue(m.vars.Electricity[r,k,c,h]) for c in CLASS[k]) for h in HOUR, k in TECH, r in REGION];

@time elec = Dict(getvalue(m.vars.Electricity[r,k,c,h]) for r in REGION, k in TECH, c in CLASS[k], h in HOUR);
@time elec = Dict((k,c) => [JuMP._getValue(m.vars.Electricity[r,k,c,h]) for r in REGION, h in HOUR] for k in TECH for c in CLASS[k]);
=#