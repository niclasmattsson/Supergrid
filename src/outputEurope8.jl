using NamedArrays

function showresults(m, drawplots, hoursperperiod, sets, params, vars, constraints)
	@unpack REGION, FUEL, TECH, CLASS, HOUR, techtype = sets
	@unpack demand = params
	@unpack CO2emissions, FuelUse, Electricity, Transmission, Capacity, TransmissionCapacity, Charging, StorageLevel = vars
	@unpack ElecDemand = constraints

	capacmat = [sum(getvalue(Capacity[r,k,c]) for c in CLASS[k]) for k in TECH, r in REGION]
	capac = NamedArray([capacmat sum(capacmat,2)], (TECH, [REGION; :TOTAL]))
	elec = NamedArray([sum(getvalue(Electricity[r,k,c,h]) for c in CLASS[k]) for h in HOUR, k in TECH, r in REGION],
				(collect(HOUR), TECH, REGION), (:HOUR, :TECH, :REGION))
	elecmat = Array(squeeze(sum(elec, 1), 1))/1000
	annualelec = NamedArray([elecmat sum(elecmat,2)], (TECH, [REGION; :TOTAL]), (:TECH, :REGION))
	totelec = Array(squeeze(sum(elec,3), 3))
	charge = NamedArray( -[getvalue(Charging[r,:battery,h]) for h in HOUR, r in REGION], (collect(HOUR), REGION), (:HOUR, :REGION))
	totcharge = Array(squeeze(sum(charge,2), 2))
	storagetechs = TECH[get.(techtype,TECH,0) .== :storage]
	existingstoragelevel = NamedArray([getvalue(StorageLevel[r,k,k == :hydro ? :x0 : :_,h]) for h in HOUR, k in storagetechs, r in REGION],
				(collect(HOUR), storagetechs, REGION), (:HOUR, :TECH, :REGION))
	tcapac = NamedArray([getvalue(TransmissionCapacity[r1,r2]) for r1 in REGION, r2 in REGION], (REGION,REGION))
	#prices = [getdual(ElecDemand[r,h]) for r in REGION, h in HOUR]
	prices = NamedArray([getdual(ElecDemand[r,h]) for r in REGION, h in HOUR], (REGION, collect(HOUR)))		# €/kWh

	displaytechs = [:nuclear, :coal, :wind, :offwind, :pv,  :csp, :gasCCGT, :bioCCGT, :hydro, :bioGT, :gasGT, :battery]
	displayorder = [findfirst(TECH, k) for k in displaytechs]

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

	function countryplot(country::Symbol)
		stackedarea(HOUR, Array(elec[:,displayorder,country]/hoursperperiod),
			labels = [k for r=1:1, k in displaytechs], size=(1850,950), tickfont=16, legendfont=16, color_palette=palette)
		plot!(HOUR,charge[:,country])
		display(plot!(HOUR,demand[country,:],c=:black))
	end

	if drawplots
		stackedarea(HOUR, Array(totelec[:,displayorder]/hoursperperiod), labels = [k for r=1:1, k in displaytechs],
							size=(1850,950), tickfont=16, legendfont=16, color_palette=palette)
		plot!(HOUR,totcharge)
		display(plot!(HOUR,vec(sum(demand,1)),c=:black))
		countryplot(:NOR)
		countryplot(:UK)
		countryplot(:SPA)
		countryplot(:GER)
		countryplot(:FRA)
		countryplot(:CEN)
		
		if true	# plot hydro storage & shadow prices
			display(plot(existingstoragelevel[:,:hydro,:NOR], size=(1850,950), tickfont=16, legendfont=16))

			plot(elec[:,:hydro,:NOR]/hoursperperiod/1000, size=(1850,950), tickfont=16, legendfont=16)
			plot!(sum(elec[:,:wind,:],2)/hoursperperiod/1000)
			display(plot!(vec(mean(prices,1))))
		end
	end

	return annualelec, capac, tcapac
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