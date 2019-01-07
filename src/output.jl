using NamedArrays, StatPlots

sumdimdrop(x::AbstractArray; dims) = dropdims(sum(x, dims=dims), dims=dims)

function showresults(model::ModelInfo)
	@unpack REGION, FUEL, TECH, CLASS, HOUR, techtype = model.sets
	@unpack demand, capacitylimits, hydrocapacity = model.params
	@unpack CO2emissions, FuelUse, Electricity, Transmission, Capacity, TransmissionCapacity, Charging, StorageLevel, Systemcost = model.vars
	@unpack ElecDemand = model.constraints
	hoursperperiod = model.hourinfo.hoursperperiod

	capacmat = [sum(getvalue(Capacity[r,k,c]) for c in CLASS[k]) for k in TECH, r in REGION]
	capac = NamedArray([capacmat sum(capacmat, dims=2)], (TECH, [REGION; :TOTAL]))
	elec = [sum(getvalue(Electricity[r,k,c,h]) for c in CLASS[k]) for h in HOUR, k in TECH, r in REGION]
	annualelec = NamedArray([sumdimdrop(elec,dims=1) sumdimdrop(elec, dims=(1,3))], (TECH, [REGION; :TOTAL]), (:TECH, :REGION))
	charge = -[getvalue(Charging[r,:battery,h]) for h in HOUR, r in REGION]
	storagetechs = [k for k in TECH if techtype[k] == :storage]
	existingstoragelevel = NamedArray([getvalue(StorageLevel[r,k,k == :hydro ? :x0 : :_,h]) for h in HOUR, k in storagetechs, r in REGION],
				(collect(HOUR), storagetechs, REGION), (:HOUR, :TECH, :REGION))
	tcapac = NamedArray([getvalue(TransmissionCapacity[r1,r2]) for r1 in REGION, r2 in REGION], (REGION,REGION))
	#prices = [getdual(ElecDemand[r,h]) for r in REGION, h in HOUR]
	prices = NamedArray([getdual(ElecDemand[r,h]) for r in REGION, h in HOUR], (REGION, collect(HOUR)))		# €/kWh

	plotly()

	palette = [
		#RGB([68,131,208]/255...),	#hydroRoR
		RGB([216,137,255]/255...),	#nuclear			or RGBA{Float64}(0.76444,0.444112,0.824298,1.0)
		RGB([119,112,71]/255...),	#coal
		#RGB([164,155,104]/255...),	#coal CCS
		RGB([199,218,241]/255...),	#wind
		RGB([149,179,215]/255...),	#wind offshore
		RGB([255,255,50]/255...),	#solarPV
		RGB([218,215,99]/255...),	#solarCSP
		RGB([255,192,0]/255...),	#CCGT
		RGB([99,172,70]/255...),	#bioCCGT
		RGB([119,165,221]/255...),	#hydro
		RGB([144,213,93]/255...),	#bioGT
		RGB([148,138,84]/255...),	#gasGT
		RGB([157,87,205]/255...),	#battery
	]

	displaytechs = [:nuclear, :coal, :wind, :offwind, :pv,  :csp, :gasCCGT, :bioCCGT, :hydro, :bioGT, :gasGT, :battery]
	techlabels = [k for r=1:1, k in displaytechs]
	displayorder = [i for (i,k) in enumerate(TECH), d in displaytechs if d == k]

	function chart(country::Symbol, plothydrostorage=false)
		if country == :BARS
			regcost = [getvalue(Systemcost[r]) for r in REGION] ./ vec(sum(annualelec, dims=1)[1:end-1]) * 1000
			totcost = sum(getvalue(Systemcost)) / sum(annualelec[:,:TOTAL]) * 1000
			lcoe = NamedArray(collect([regcost; totcost]'), (["system cost (€/MWh)"], [REGION; :TOTAL]))
			display(lcoe)

			display(groupedbar(String.(REGION),collect(annualelec[displayorder,1:end-1]'/1000), labels=techlabels, bar_position = :stack, size=(1850,950), line=0, tickfont=16, legendfont=16, color_palette=palette))
			totelec = [sumdimdrop(annualelec[:,1:8],dims=2) sumdimdrop(annualelec[:,9:15],dims=2) sumdimdrop(annualelec[:,16:21],dims=2) annualelec[:,:TOTAL]]
			display(groupedbar(["EU","CAS","China","TOTAL"],collect(totelec[displayorder,:]'/1000), labels=techlabels, bar_position = :stack, size=(500,950), line=0, tickfont=16, legendfont=16, color_palette=palette))
			return
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
		regcharge = sumdimdrop(charge[:,regs], dims=2)
		regdemand = sumdimdrop(demand[regs,:], dims=1)
		reghydrostorage = sumdimdrop(existingstoragelevel[:,[:hydro],regs], dims=3)

		composite = plot(layout = 4, size=(1850,950), legend=false)
		for (i,k) in enumerate([:wind, :offwind, :pv, :hydro])
			colors = [palette[findfirst(displaytechs .== k)]; RGB(0.9,0.9,0.9)]
			used = [sum(getvalue(Capacity[r,k,c]) for r in REGION[regs]) for c in CLASS[k]]
			lims = [sum(k == :hydro ? hydrocapacity[r,c] : capacitylimits[r,k,c] for r in REGION[regs]) for c in CLASS[k]]
			groupedbar!(String.(CLASS[k]), [used lims-used], subplot=i, bar_position = :stack, line=0, color_palette=colors)
		end
		display(composite)

		plothydrostorage && display(plot(reghydrostorage, size=(1850,950), tickfont=16, legendfont=16))

		level = [getvalue(StorageLevel[r,:battery,:_,h])*100 for h in HOUR, r in REGION]
		reglevel = sumdimdrop(level[:,regs], dims=2)
		display(plot(HOUR,[-regcharge regelec[:,12] reglevel],size=(1850,950)))

		stackedarea(HOUR, regelec, labels=techlabels, size=(1850,950), line=0, tickfont=16, legendfont=16, color_palette=palette)
		plot!(HOUR, regcharge)
		display(plot!(HOUR, regdemand, c=:black))
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
=#