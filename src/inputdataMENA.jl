using HDF5, MAT

makesets(hourinfo) = makesets([:MOR, :ALG, :TUN, :LIB, :EGY, :ISP, :LEB, :JOR, :SYR, :TURK, :IRAN, :IRAQ, :SAUDI], hourinfo)
makesets(r::Symbol, hourinfo) = makesets([r], hourinfo)

function makesets(REGION::Vector{Symbol}, hourinfo)
	techdata = Dict(
		:name => [:pv,  :csp, :wind, :offwind, :hydroRoR, :hydroDam, :coal,    :gasGT,   :gasCCGT, :bioGT,   :bioCCGT, :nuclear, :battery],
		:type => [:vre,	:vre, :vre,  :vre,     :vre,      :storage,  :thermal, :thermal, :thermal, :thermal, :thermal, :thermal, :storage],
		:fuel => [:_,   :_,	  :_,    :_,       :_,        :_,        :coal,    :gas,     :gas,     :biogas,  :biogas,  :uranium, :_]
	)
	numtechs = length(techdata[:name])
	vreclass = Symbol["$letter$number" for letter in ["a"] for number = 1:5]		# add B classes later
	noclass = [:_]
	techtype = Dict(techdata[:name][i] => techdata[:type][i] for i=1:numtechs)
	techfuel = Dict(techdata[:name][i] => techdata[:fuel][i] for i=1:numtechs)

	TECH = techdata[:name]
	FUEL = [:_, :coal, :gas, :biogas, :uranium]
	CLASS = Dict(k => techtype[k] == :vre && k != :hydroRoR ? vreclass : noclass for k in TECH)

	HOUR = 1:Int(length(hourinfo.hourindexes)/hourinfo.sampleinterval)		# later use hoursperyear() in helperfunctions

	return Sets(REGION, FUEL, TECH, CLASS, HOUR, techtype, techfuel)
end

# resample hour dimension of array a (indicated by hourdim) using hourindexes in hourinfo structure,
# then reduce hours further by sampleinterval
function reducehours(a, hourdim, hourinfo)
	sampleinterval = hourinfo.sampleinterval
	aa = slicedim(a, hourdim, hourinfo.hourindexes)
	out = slicedim(aa, hourdim, 1:sampleinterval:size(aa,hourdim))	# sample every nth hour
	if true		# true: averaging   false: sampling
		for i = 2:sampleinterval
			out += slicedim(aa, hourdim, i:sampleinterval:size(aa,hourdim))
		end
		out = out / sampleinterval
	end
	return out
end


function makeparameters(sets, hourinfo)
	@unpack REGION, FUEL, TECH, CLASS, HOUR = sets

	year = 2016
	hoursperyear = 8760
	hoursperperiod = hourinfo.hoursperperiod

	discountrate = 0.05
	initialhydrostoragelevel = 0.7		# make this tech dependent later

	numregions = length(REGION)
	nhours = length(HOUR)

	path = joinpath(dirname(@__FILE__), "..")

	# demand data is not currently based on same year as solar & wind data!!!
	file = h5open("$path/inputdata/InputMENA.h5", "r")
	readdemand::Matrix{Float64} = read(file, "DemandMENA3")'/1000
	readRoR::Matrix{Float64} = read(file, "FakeROR2")'/1000
	readDam::Matrix{Float64} = read(file, "AnnualDam") *1000
	readcapacDam::Matrix{Float64} = read(file, "CapDam") /1000
	readdistance::Matrix{Float64} = read(file, "Distance")
	demand = AxisArray(reducehours(readdemand, 2, hourinfo), REGION, HOUR)		# GW
	hydroRoR = AxisArray(reducehours(readRoR, 2, hourinfo), REGION, HOUR)		# GW
	annualDam = AxisArray(vec(readDam), REGION)                              	# GWh/year
	capacDam = AxisArray(vec(readcapacDam), REGION)  							# GW
	distance = readdistance         											# km
	close(file)

	capacRoR = maximum(hydroRoR,2)  #MW?
	cfRoR = AxisArray(hydroRoR ./ capacRoR, REGION, HOUR)
	cfRoR[isnan.(cfRoR)] = 0
	annualRoR = AxisArray(hoursperperiod * sum(hydroRoR,2), REGION)		# GWh/year
	annualdemand = AxisArray(hoursperperiod * sum(demand,2), REGION)	# GWh/year
	annualcfDam = AxisArray(annualDam / hoursperyear ./ capacDam, REGION)
	annualcfDam[isnan.(annualcfDam)] = 0
	cfDam = copy(cfRoR)					#????????????? Samma regnflöde i dam som i ROR?
	hydroinflow = copy(cfDam)
	for r in REGION
		cfDam[r,:] = cfDam[r,:] / mean(cfDam[r,:]) * annualcfDam[r]
		hydroinflow[r,:] = hoursperperiod * cfDam[r,:] * capacDam[r]		# GWh/period
	end   #Vad händer i denna loop??
	hydrocapacity = AxisArray(zeros(numregions,2), REGION, [:hydroRoR,:hydroDam])	# GW
	hydrocapacity[:,:hydroRoR] = capacRoR
	hydrocapacity[:,:hydroDam] = capacDam

	hydrostoragecapacity = [	# TWh
		:MOR    :ALG    :TUN    :LIB    :EGY    :ISP    :LEB    :JOR    :SYR    :TURK    :IRAN    :IRAQ    :SAUDI
		0.839	0.107	0.02	0		4.57	0.008	0.22	0.02    0.92    22.3     4.6      1.47     0
	]

	dischargetime = AxisArray(zeros(numregions,2), REGION, [:hydroDam,:battery])
	dischargetime[:,:battery] = 8
	dischargetime[:,:hydroDam] = hydrostoragecapacity[2,:]./capacDam * 1000 # undefined for zeroes.
	dischargetime[:LIB,:] = 0 #quickfix för att inte få NaN, eftersom capacDam för LIB är 0.
	dischargetime[:SAUDI,:] = 0
	#transmissioncostdata = [	# €/kW
		#:_		:MOR    :ALG    :TUN    :LIB    :EGY    :ISP    :LEB    :JOR    :SYR    :TURK    :IRAN    :IRAQ    :SAUDI
		#:MOR	0		0		600		1200	0		1000	0		0       0       0        0        0        0
		#:ALG	0		0		500		600		1200	0		500		1000    0       0        0        0        0
		#:TUN	600		500		0		900		0		500		0		400		0       0        0        0        0
		#:LIB	1200	600		900		0		0		0		0		0		0       0        0        0        0
		#:EGY	0		1200	0		0		0		0		0		650		0       0        0        0        0
		#:ISP	1000	0		500		0		0		0		0		400		0       0        0        0        0
		#:LEB	0		500		0		0		0		0		0		0		0       0        0        0        0
		#:JOR	0		1000	400		0		650		400		0		0		0       0        0        0        0
		#:SYR	0       0       0      0        0		0       0       0       0       0		 0        0        0
		#:TURK   0       0       0      0        0		0       0       0       0       0		 0        0        0
		#:IRAN   0       0       0      0        0		0       0       0       0       0		 0        0        0
		#:IRAQ   0       0       0      0        0		0       0       0       0       0		 0        0        0
		#:SAUDI  0       0       0      0        0		0       0       0       0       0		 0        0        0
	#]
	#transmissioncost = AxisArray(Float64.(transmissioncostdata[2:end,2:end]), REGION, REGION)		# €/kW
	#transmissionlosses = AxisArray(fill(0.05,numregions,numregions), REGION, REGION)		# maybe proportional to distance (costs) later?
	smalltransmissionpenalty = 0.1		# €/MWh elec
	transmissioncost = AxisArray(distance * 2032 * 0.85, REGION, REGION)
	transmissionlosses = AxisArray(distance * 0.02, REGION, REGION)
	investdata = [
		#				investcost	variablecost	fixedcost	lifetime	efficiency
		#				€/kW		€/MWh elec		€/kW/year	years
		:gasGT			380			0.7				50			30			0.4
		:gasCCGT		760			0.8				50			30			0.7
		:coal			1400		0				80			35			0.4
		:bioGT			380			0.7				50			30			0.4
		:bioCCGT		760			0.8				50			30			0.7
		:nuclear		5100		0				160			60			0.4
		:wind			1400		0				44			25			1
		:offwind		2800		0				100			25			1
		:transmission	NaN			0				0			40			NaN
		:battery		1200		0				0			10			0.85	# 8h discharge time, 1200 €/kW = 150 €/kWh
		:pv				600			0				19			25			1
		:csp			1200		0				50			30			1	# add CSP data later
		# :hydroRoR and :hydroDam are sunk costs
		:hydroRoR		0			0				0			80			1
		:hydroDam		0			0				0			80			1	# change hydroDam efficiency later
	]
	investtechs = investdata[:,1]
	investdata = Float64.(investdata[:,2:end])
	investcost = AxisArray(investdata[:,1], investtechs)	# €/kW
	variablecost = AxisArray(investdata[:,2], investtechs)	# €/MWh elec
	fixedcost = AxisArray(investdata[:,3], investtechs)		# €/kW/year
	lifetime = AxisArray(investdata[:,4], investtechs)		# years
	efficiency = AxisArray(investdata[:,5], investtechs)

	fuelcost = AxisArray(Float64[0, 8, 30, 60, 8], [:_, :coal, :gas, :biogas, :uranium])		# €/MWh fuel

	crf = AxisArray(discountrate ./ (1 - 1./(1+discountrate).^lifetime), investtechs)

	emissionsCO2 = AxisArray(zeros(length(FUEL)), FUEL)
	emissionsCO2[[:coal,:gas]] = [0.330, 0.202]		# kgCO2/kWh fuel (or ton/MWh or kton/GWh)

	# do something with B classes (and pvrooftop) later
	windvars = matread("$path/inputdata/GISdata_wind2016_mena.mat")
	solarvars = matread("$path/inputdata/GISdata_solar2016_mena.mat")

	cf = AxisArray(ones(numregions,length(TECH),length(CLASS[:pv])+1,nhours), REGION, TECH, [CLASS[:pv]; :_], HOUR)
	capacitylimits = AxisArray(zeros(numregions,4,length(CLASS[:pv])), REGION, [:wind, :offwind, :pv, :csp], CLASS[:pv])

	# sync wind & solar time series with demand
	# (ignore 2016 extra leap day for now, fix this later)
	# note first wind data is at 00:00 and first solar data is at 07:00
	# assume first demand data is at 00:00
	cf[:,:wind,1:5,:] = permutedims(reducehours(windvars["CFtime_windonshoreA"][25:hoursperyear+24,:,:], 1, hourinfo), [2,3,1])
	cf[:,:offwind,1:5,:] = permutedims(reducehours(windvars["CFtime_windoffshore"][25:hoursperyear+24,:,:], 1, hourinfo), [2,3,1])
	cf[:,:pv,1:5,:] = permutedims(reducehours(solarvars["CFtime_pvplantA"][18:hoursperyear+17,:,:], 1, hourinfo), [2,3,1])
	cf[:,:csp,1:5,:] = permutedims(reducehours(solarvars["CFtime_cspplantA"][18:hoursperyear+17,:,:], 1, hourinfo), [2,3,1])
	cf[:,:hydroRoR,:_,:] = cfRoR
	cf[isnan.(cf)] = 0
	cf[cf .< 0.01] = 0		# set small values to 0 for better numerical stability

	capacitylimits[:,:wind,:] = windvars["capacity_onshoreA"]
	capacitylimits[:,:offwind,:] = windvars["capacity_offshore"]
	capacitylimits[:,:pv,:] = solarvars["capacity_pvplantA"]
	capacitylimits[:,:csp,:] = solarvars["capacity_cspplantA"]



	return Params(cf, transmissionlosses, demand, hydrocapacity, hydroinflow, capacitylimits,
		efficiency, dischargetime, initialhydrostoragelevel, emissionsCO2,
		fuelcost, variablecost, smalltransmissionpenalty, investcost, crf, fixedcost, transmissioncost)
end
