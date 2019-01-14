using HDF5, MAT, DelimitedFiles, Statistics, Dates, TimeZones

 # :NOR,:FRA,:GER,:UK,:MED,:BAL,:SPA,:CEN,:BUK,:TCC,:KZK,:CAS,:RU_C,:RU_SW,:RU_VL,:CH_N,:CH_NE,:CH_E,:CH_SC,:CH_SW,:CH_NW
 # makesets(hourinfo) = makesets([:NOR, :FRA, :GER, :UK, :MED, :BAL, :SPA, :CEN, :CH_N, :CH_NE, :CH_E, :CH_SC, :CH_SW, :CH_NW], hourinfo)
function makesets(hourinfo)
	path = joinpath(dirname(@__FILE__), "..")
	distancevars = matread("$path/inputdata/distances_eurasia21.mat")
	regionlist = Symbol.(vec(distancevars["regionlist"]))
	makesets(regionlist, hourinfo)
end

makesets(r::Symbol, hourinfo) = makesets([r], hourinfo)

function makesets(REGION::Vector{Symbol}, hourinfo)
	techdata = Dict(
		:name => [:pv,  :csp, :wind, :offwind, :hydro,	  :coal,    :gasGT,   :gasCCGT, :bioGT,   :bioCCGT, :nuclear, :battery],
		:type => [:vre,	:vre, :vre,  :vre,     :storage,  :thermal, :thermal, :thermal, :thermal, :thermal, :thermal, :storage],
		:fuel => [:_,   :_,	  :_,    :_,       :_,        :coal,    :gas,     :gas,     :biogas,  :biogas,  :uranium, :_]
	)
	nstorageclasses = (4,4)		# (cost classes, reservoir classes)
	nvreclasses = 5

	numtechs = length(techdata[:name])
	reservoirs = collect('a':'z')[1:nstorageclasses[2]]
	vreclass = [Symbol("$letter$number") for letter in ["a", "b"] for number = 1:nvreclasses]
	hydroclass = [:x0;  [Symbol("$letter$number") for letter in reservoirs for number = 1:nstorageclasses[1]]]
	noclass = [:_]
	techtype = Dict(techdata[:name][i] => techdata[:type][i] for i=1:numtechs)
	techfuel = Dict(techdata[:name][i] => techdata[:fuel][i] for i=1:numtechs)

	TECH = techdata[:name]
	FUEL = [:_, :coal, :gas, :biogas, :uranium]
	CLASS = Dict(k => k == :hydro ? hydroclass : techtype[k] == :vre ? vreclass : noclass for k in TECH)
	CLASS[:transmission] = noclass
	STORAGECLASS = Dict(k => k == :hydro ? [:x0;  Symbol.(reservoirs)] : [:_] for k in TECH)

	reservoirclass = Dict(r => [Symbol("$r$number") for number = 1:nstorageclasses[1]] for r in Symbol.(reservoirs))
	reservoirclass[:x0] = [:x0]
	reservoirclass[:_] = [:_]

	HOUR = 1:Int(length(hourinfo.hourindexes)/hourinfo.sampleinterval)		# later use hoursperyear() in helperfunctions

	return Sets(REGION, FUEL, TECH, CLASS, STORAGECLASS, HOUR, techtype, techfuel, reservoirclass)
end

# resample hour dimension of array a (indicated by hourdim) using hourindexes in hourinfo structure,
# then reduce hours further by sampleinterval
function reducehours(a, hourdim, hourinfo)
	sampleinterval = hourinfo.sampleinterval
	aa = copy(selectdim(a, hourdim, hourinfo.hourindexes))
	out = copy(selectdim(aa, hourdim, 1:sampleinterval:size(aa,hourdim)))	# sample every nth hour
	if true		# true: averaging   false: sampling
		for i = 2:sampleinterval
			out += copy(selectdim(aa, hourdim, i:sampleinterval:size(aa,hourdim)))
		end
		out = out / sampleinterval
	end
	return out
end

# reduce regions from 10 (in Lina's input data) to 8 (in model)
# :MED = :IT + :GR,    :BAL (new) = :BAL (old) + :POL
function ten2eight(a)
	# REG10 = [:NOR, :IT, :FRA, :GER, :UK, :GR, :BAL, :POL, :SPA, :CEN]
	# REGION = [:NOR, :FRA, :GER, :UK, :MED, :BAL, :SPA, :CEN]
	out = a[[1,3,4,5,6,7,9,10],:]
	out[5,:] = a[2,:] + a[6,:]
	out[6,:] = a[7,:] + a[8,:]
	return out
end

CRF(r,T) = r / (1 - 1/(1+r)^T)

function makeparameters(sets, hourinfo)
	@unpack REGION, FUEL, TECH, CLASS, HOUR = sets

	year = 2016
	hoursperyear = 8760
	hoursperperiod = Int(hourinfo.hoursperperiod)

	discountrate = 0.05
	initialhydrostoragelevel = 0.7		# make this tech dependent later
	minflow_existinghydro = 0.4

	numregions = length(REGION)
	nhours = length(HOUR)
	nhydro = length(CLASS[:hydro])

	path = joinpath(dirname(@__FILE__), "..")

	# read regional distances and SSP data from Matlab file
	distancevars = matread("$path/inputdata/distances_eurasia21.mat")
	population = vec(distancevars["population"])	# Mpeople in SSP2 2050
	sspdemand = vec(distancevars["demand"])			# TWh/year (demand in SSP2 2050 major regions downscaled to countries using BP 2017 stats)

	demand = AxisArray(zeros(numregions, nhours), REGION, HOUR)		# GW

	# read synthetic demand data (using local time) and shift to UTC
	# (note: not currently based on same year as solar & wind data!!!)
	# if time zone code errors then run TimeZones.TZData.compile(max_year=2200), see https://timezonesjl.readthedocs.io/en/stable/faq/
	zones = ["Europe/Oslo","Europe/Paris","Europe/Berlin","Europe/London","Europe/Rome","Europe/Warsaw","Europe/Madrid","Europe/Budapest","Europe/Sofia","Europe/Istanbul","Asia/Almaty","Asia/Ashgabat","Europe/Moscow","Europe/Moscow","Europe/Moscow","Asia/Shanghai","Asia/Shanghai","Asia/Shanghai","Asia/Shanghai","Asia/Shanghai","Asia/Shanghai"]	
	hourrange = DateTime(2050,1,1,0):Hour(1):DateTime(2050,12,31,23)
	utc = [ZonedDateTime(h, TimeZone("UTC")) for h in hourrange]
	for (i,reg) in enumerate(REGION)
		data = readdlm("$path/inputdata/syntheticdemand/synthetic2050_region$(i)_$reg.csv", ',')
		demandlocaltime = data[2:end, 2]
		timezone = TimeZone(zones[i])
		localtime = [astimezone(ut, timezone) for ut in utc]
		localoffset = [Dates.value.(lt.zone.offset)÷3600 for lt in localtime]
		indexoffset = mod.((1:8760) + localoffset .- 1, 8760) .+ 1
		demandutc = demandlocaltime[indexoffset]
		demand[i,:] = reducehours(demandutc, 1, hourinfo) * 1000
		# println("$reg ($i): ", sspdemand[i], " ", mean(demand[i,:])*8760/1000)	# check total regional demand
	end

	hydrovars = matread("$path/inputdata/GISdata_hydro_eurasia21.mat")
	hydrocapacity = AxisArray(zeros(numregions,nhydro), REGION, CLASS[:hydro])
	hydroeleccost = AxisArray(zeros(numregions,nhydro), REGION, CLASS[:hydro])
	monthlyinflow = AxisArray(zeros(numregions,nhydro,12), REGION, CLASS[:hydro], 1:12)
	cfhydroinflow = AxisArray(zeros(numregions,nhydro,nhours), REGION, CLASS[:hydro], HOUR)
	dischargetime = AxisArray(zeros(numregions,2,1+nhydro), REGION, [:hydro,:battery], [CLASS[:hydro]; :_])
	
	hydrocapacity[:,:x0] = hydrovars["existingcapac"]
	hydrocapacity[:,2:end] = reshape(hydrovars["potentialcapac"], numregions, nhydro-1)
	hydrocapacity[isnan.(hydrocapacity)] = zeros(sum(isnan.(hydrocapacity)))

	# eleccost = capcost * crf / (CF * 8760)  =>   eleccost2/eleccost1 = crf2/crf1
	# 1$ = 0.9€ (average 2015-2017) 
	hydroeleccost[:,2:end] = reshape(hydrovars["potentialmeancost"], numregions, nhydro-1)		# $/kWh with 10% discount rate
	hydroeleccost[:,:] = hydroeleccost[:,:] * CRF(discountrate,40)/CRF(0.1,40) * 0.9 * 1000		# €/MWh    (0.9 €/$)
	hydroeleccost[isnan.(hydroeleccost)] = fill(999, sum(isnan.(hydroeleccost)))

	monthlyinflow[:,:x0,:] = hydrovars["existinginflowcf"]
	monthlyinflow[:,2:end,:] = reshape(hydrovars["potentialinflowcf"], numregions, nhydro-1, 12)
	monthlyinflow[isnan.(monthlyinflow)] = zeros(sum(isnan.(monthlyinflow)))

	hydrostoragecapacity = [	# TWh
		:NOR	:FRA	:GER	:UK		:MED	:BAL	:SPA	:CEN
		121.43	3.59	0		0		9.2		0		16.6	7.4
	]
	dischargetime[1:8,:hydro,:x0] = hydrostoragecapacity[2,:]./hydrocapacity[1:8,:x0] * 1000
	dischargetime[[:GER,:UK,:BAL],:hydro,:x0] .= 300
	dischargetime[9:21,:hydro,:x0] .= 168*6		# assume average discharge time 6 weeks for existing hydro in Asia & China
	dischargetime[:,:hydro,2:end-1] = reshape(hydrovars["potentialmeandischargetime"], numregions, nhydro-1)
	dischargetime[:,:battery,:_] .= 8
	dischargetime[isnan.(dischargetime)] = fill(10000, sum(isnan.(dischargetime)))
	dischargetime[dischargetime .> 10000] = fill(10000, sum(dischargetime .> 10000))

	# monthly to hourly hydro inflow
	dayspermonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
	lasthour = 24 ÷ hoursperperiod * cumsum(dayspermonth)
	firsthour = [1; 1 .+ lasthour[1:end-1]]
	for m = 1:12
		for i = firsthour[m]:lasthour[m]
			cfhydroinflow[:,:,i] = monthlyinflow[:,:,m]
		end
	end
	cfhydroinflow[cfhydroinflow .< 0.01] = zeros(sum(cfhydroinflow .< 0.01))

	distances = distancevars["distances"]
	connected = distancevars["connected"]
	connectedoffshore = distancevars["connectedoffshore"]

	connected[3,19] = connected[19,3] = true

	# from Bogdanov & Breyer (2016) "North-East Asian Super Grid..."
	transmissioncostdata = connected .* (180 .+ 0.612*distances) .+ connectedoffshore .* (180 .+ 0.992*distances)
	transmissionfixedcostdata = connected .* (1.8 .+ 0.0075*distances) .+ connectedoffshore .* (1.8 .+ 0.0010*distances)
	transmissioninvestcost = AxisArray(transmissioncostdata, REGION, REGION)		# €/kW
	transmissionfixedcost = AxisArray(transmissionfixedcostdata, REGION, REGION)		# €/kW
	transmissionlossdata = (connected .| connectedoffshore) .* (0.014 .+ 0.016*distances/1000)
	transmissionlosses = AxisArray(transmissionlossdata, REGION, REGION)
	smalltransmissionpenalty = 0.1		# €/MWh elec

	transmissionislands = AxisArray(zeros(Bool, numregions,numregions), REGION, REGION)
	islandindexes = [1:8, 9:15, 16:21]
	for ndx in islandindexes
		transmissionislands[ndx,ndx] .= true
	end

	# PV and battery costs have high/mid/low costs:  high = 1.5*mid, low = 0.5*mid
	techdata = [
		#				investcost 	variablecost	fixedcost	lifetime	efficiency	rampingrate
		#				€/kW		€/MWh elec		€/kW/year	years					share of capacity per hour
		:gasGT			500			1				10			30			0.4			1
		:gasCCGT		800			1				16			30			0.6			0.3
		:coal			1600		2				48			30			0.45		0.15
		:bioGT			500			1				10			30			0.4			1
		:bioCCGT		800			1				16			30			0.6			0.3
		:nuclear		5000		3				150			50			0.4			0.05
		:wind			1200		0				36			25			1			1
		:offwind		2000		0				60			25			1			1
		:transmission	NaN			0				NaN			50			NaN			1
		:battery		1200		0				12			10			0.9			1	# 8h discharge time, 1200 €/kW = 150 €/kWh
		:pv				800			0				16			25			1			1
		:csp			1200		0				36			30			1			1	# add CSP data later
		:hydro			10			0				0			80			1			1	# small artificial investcost so it doesn't overinvest in free capacity 
	]
	techs = techdata[:,1]
	techdata = Float64.(techdata[:,2:end])
	baseinvestcost = AxisArray(techdata[:,1], techs)	# €/kW
	variablecost = AxisArray(techdata[:,2], techs)		# €/MWh elec
	fixedcost = AxisArray(techdata[:,3], techs)			# €/kW/year
	lifetime = AxisArray(techdata[:,4], techs)			# years
	efficiency = AxisArray(techdata[:,5], techs)
	rampingrate = AxisArray(techdata[:,6], techs)

	# fuel cost references:
	# 1. https://www.gov.uk/government/statistical-data-sets/prices-of-fuels-purchased-by-major-power-producers
	# 2. https://oilprice.com/Energy/Natural-Gas/European-Natural-Gas-Prices-Are-Set-To-Rise-Further.html
	# 3. https://www.bloomberg.com/news/articles/2018-09-03/coal-nears-100-in-europe-as-china-s-power-demand-draws-in-fuel
	# 4. https://www.frisch.uio.no/ressurser/LIBEMOD/pdf/phase_out_28mai2015_golombek_powerpoint.pdf
	# 5. http://www.world-nuclear.org/information-library/economic-aspects/economics-of-nuclear-power.aspx
	# 6. https://www.gasforclimate2050.eu/files/files/Ecofys_Gas_for_Climate_Report_Study_March18.pdf  (page 19, section 3.4, figure 7)
	# Sepulveda/Jenkins:  gas & biogas 21 €/MWh, uranium 3 €/MWh
	# 1: coal 11-12 €/MWh, gas 19-21 €/MWh,  2: gas 20-30 €/MWh,  3: coal 70-90 €/ton = (25 MJ/kg) = 2.8-3.6 €/GJ = 10-13 €/MWh
	# 4: gas 45*.5 = 22 €/MWh, coal 22.3*.4 = 9 €/MWh, bio 26.4*.4 = 11 €/MWh, nuclear 6.7*.35 = 2.3 €/MWh
	# 5: nuclear fuel pellets 0.39 USD/kWh = 3.2 €/MWh    (see also Stuff/Nuclear fuel costs.xlsx)
	# 6: biomethane anaerobic digestion 96 €/MWh (2015), 60 €/MWh (2050), thermal gasification 37 €/MWh (2050)
	
	fuelcost = AxisArray(Float64[0, 11, 22, 37, 3.2], [:_, :coal, :gas, :biogas, :uranium])		# €/MWh fuel

	crf = AxisArray(discountrate ./ (1 .- 1 ./(1+discountrate).^lifetime), techs)

	emissionsCO2 = AxisArray(zeros(length(FUEL)), FUEL)
	emissionsCO2[[:coal,:gas]] = [0.330, 0.202]		# kgCO2/kWh fuel (or ton/MWh or kton/GWh)

	# do something with B classes (and pvrooftop) later
	windvars = matread("$path/inputdata/GISdata_wind2016_eurasia21.mat")
	solarvars = matread("$path/inputdata/GISdata_solar2016_eurasia21.mat")
	# windvars = matread("$path/inputdata/GISdata_wind2016_1000km_eurochine14.mat")
	# solarvars = matread("$path/inputdata/GISdata_solar2016_1000km_eurochine14.mat")

	allclasses = union(sets.CLASS[:pv], sets.CLASS[:hydro], [:_])
	cf = AxisArray(ones(numregions,length(TECH),length(allclasses),nhours), REGION, TECH, allclasses, HOUR)
	classlimits = AxisArray(zeros(numregions,4,length(CLASS[:pv])), REGION, [:wind, :offwind, :pv, :csp], CLASS[:pv])

	# sync wind & solar time series with demand
	# (ignore 2016 extra leap day for now, fix this later)
	# note first wind data is at 00:00 and first solar data is at 07:00
	# assume first demand data is at 00:00
	cf[:,:wind,1:5,:] = permutedims(reducehours(windvars["CFtime_windonshoreA"][25:hoursperyear+24,:,:], 1, hourinfo), [2,3,1])
	cf[:,:offwind,1:5,:] = permutedims(reducehours(windvars["CFtime_windoffshore"][25:hoursperyear+24,:,:], 1, hourinfo), [2,3,1])
	cf[:,:pv,1:5,:] = permutedims(reducehours(solarvars["CFtime_pvplantA"][18:hoursperyear+17,:,:], 1, hourinfo), [2,3,1])
	cf[:,:csp,1:5,:] = permutedims(reducehours(solarvars["CFtime_cspplantA"][18:hoursperyear+17,:,:], 1, hourinfo), [2,3,1])
	cf[:,:wind,6:10,:] = permutedims(reducehours(windvars["CFtime_windonshoreB"][25:hoursperyear+24,:,:], 1, hourinfo), [2,3,1])
	cf[:,:pv,6:10,:] = permutedims(reducehours(solarvars["CFtime_pvplantB"][18:hoursperyear+17,:,:], 1, hourinfo), [2,3,1])
	cf[:,:csp,6:10,:] = permutedims(reducehours(solarvars["CFtime_cspplantB"][18:hoursperyear+17,:,:], 1, hourinfo), [2,3,1])
	cf[isnan.(cf)] = zeros(sum(isnan.(cf)))
	cf[cf .< 0.01] = zeros(sum(cf .< 0.01))		# set small values to 0 for better numerical stability

	classlimits[:,:wind,1:5] = windvars["capacity_onshoreA"]
	classlimits[:,:offwind,1:5] = windvars["capacity_offshore"]
	classlimits[:,:pv,1:5] = solarvars["capacity_pvplantA"]
	classlimits[:,:csp,1:5] = solarvars["capacity_cspplantA"]
	classlimits[:,:wind,6:10] = windvars["capacity_onshoreB"]
	classlimits[:,:pv,6:10] = solarvars["capacity_pvplantB"]
	classlimits[:,:csp,6:10] = solarvars["capacity_cspplantB"]

	investcost = AxisArray(zeros(length(techs),length(allclasses)), techs, allclasses)	# €/kW
	for k in techs, c in CLASS[k]
		investcost[k,c] = baseinvestcost[k]
	end
	for k in [:wind,:pv,:csp]
		investcost[k,6:10] .= baseinvestcost[k]*1.1
	end

	# # check demand/solar synchronization
	# plotly()
	# for r = 1:numregions
	# 	tt1 = 8760÷2÷hoursperperiod		# test winter, spring, summer (÷12, ÷3, ÷2)
	# 	tt = tt1:tt1+2*24÷hoursperperiod
	# 	qq = [demand[r,tt] maximum(cf[r,:pv,1:5,tt],dims=1)']
	# 	display(plot(qq./maximum(qq,dims=1), size=(1850,950)))
	# end

	return Params(cf, transmissionlosses, demand, hydrocapacity, cfhydroinflow, classlimits, transmissionislands,
		efficiency, rampingrate, dischargetime, initialhydrostoragelevel, minflow_existinghydro, emissionsCO2, fuelcost,
		variablecost, smalltransmissionpenalty, investcost, crf, fixedcost, transmissioninvestcost, transmissionfixedcost, hydroeleccost)
end
