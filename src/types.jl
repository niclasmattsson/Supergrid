struct Sets
	REGION			::Vector{Symbol}
	FUEL			::Vector{Symbol}
	TECH			::Vector{Symbol}
	CLASS			::Dict{Symbol, Vector{Symbol}}
	STORAGECLASS	::Dict{Symbol, Vector{Symbol}}
	HOUR			::UnitRange{Int64}
	techtype		::Dict{Symbol,Symbol}
	techfuel		::Dict{Symbol,Symbol}
	reservoirclass	::Dict{Symbol, Vector{Symbol}}
	dataregions		::Vector{Symbol}
end

# need to specify AxisArray types in more detail
struct Params
	cf							::AxisArray{Float64,4}
	transmissionlosses			::AxisArray{Float64,2}		
	demand						::AxisArray{Float64,2}	
	hydrocapacity				::AxisArray{Float64,2}	
	cfhydroinflow				::AxisArray{Float64,3}
	classlimits					::AxisArray{Float64,3}
	transmissionislands			::AxisArray{Bool,2}
	efficiency					::AxisArray{Float64,1}
	rampingrate					::AxisArray{Float64,1}
	dischargetime				::AxisArray{Float64,3}
	initialstoragelevel			::Float64
	minflow_existinghydro		::Float64
	emissionsCO2				::AxisArray{Float64,1}	
	fuelcost					::AxisArray{Float64,1}	
	variablecost				::AxisArray{Float64,1}	
	smalltransmissionpenalty	::Float64
	investcost					::AxisArray{Float64,2}
	crf							::AxisArray{Float64,1}
	fixedcost					::AxisArray{Float64,1}
	transmissioninvestcost		::AxisArray{Float64,2}
	transmissionfixedcost		::AxisArray{Float64,2}
	hydroeleccost				::AxisArray{Float64,2}
	solarcombinedarea			::AxisArray{Float64,3}
	pv_density					::Float64
	csp_density					::Float64
	cspsolarmultiple			::Float64
end

struct Vars
	Systemcost					::JuMP.JuMPArray{JuMP.Variable,1}
	CO2emissions				::JuMP.JuMPArray{JuMP.Variable,1}
	FuelUse						::JuMP.JuMPArray{JuMP.Variable,2}
	Electricity					::JuMP.JuMPDict{JuMP.Variable,4}
	AnnualGeneration			::JuMP.JuMPArray{JuMP.Variable,2}
	Charging					::JuMP.JuMPDict{JuMP.Variable,3}
	StorageLevel				::JuMP.JuMPDict{JuMP.Variable,4}
	Transmission				::JuMP.JuMPArray{JuMP.Variable,3}
	TransmissionCapacity		::JuMP.JuMPArray{JuMP.Variable,2}
	Capacity					::JuMP.JuMPDict{JuMP.Variable,3}
	SolarCapacity				::JuMP.JuMPArray{JuMP.Variable,4}
end

# add type info here too
struct Constraints
	ElecCapacity
	ElecDemand
	RampingDown
	RampingUp
	StorageBalance
	MaxStorageCapacity
	InitialStorageLevel
	MaxTransmissionCapacity
	TwoWayStreet
	NoTransmission
	NoHydroCharging
	ChargingNeedsBattery
	Calculate_AnnualGeneration
	Calculate_FuelUse
	TotalCO2
	Totalcosts
end

struct HourSampling
	hours			::Int			# unit: hours/period
	selectdays		::Int
	skipdays		::Int
	hoursperperiod	::Float64		# not same as hours because cycles/year maybe not integer
	hourindexes		::Vector{Int}	# select indexes before using hours to sample hours
end

HourSampling(options::Dict) = HourSampling(options[:hours], options[:selectdays], options[:skipdays])

function HourSampling(hours, selectdays, skipdays)
	@assert hours in (1,2,3,4,6) "hours must be one of (1,2,3,4,6)"
	hourspercycle = (selectdays + skipdays) * 24
	cyclesperyear = floor(8760/hourspercycle)
	periodsperyear = cyclesperyear * hourspercycle / hours
	hoursperperiod = 8760 / periodsperyear * (1 + skipdays/selectdays)
	hourindexes = [(c-1)*hourspercycle + h for c=1:cyclesperyear for h=1:hourspercycle if h <= selectdays*24]
	HourSampling(hours, selectdays, skipdays, hoursperperiod, hourindexes)
end

struct ModelInfo
	modelname	::JuMP.Model
	sets		::Sets
	params		::Params
	vars		::Vars
	constraints	::Constraints
	hourinfo	::HourSampling
	options		::Dict{Symbol,Any}
end

struct Results
	Status						::Symbol
	options						::Dict{Symbol,Any}
	hourinfo					::HourSampling
	sets						::Sets
	params						::Dict{Symbol,Any}
	Systemcost					::AxisArray{Float64,1}
	CO2emissions				::AxisArray{Float64,1}
	FuelUse						::AxisArray{Float64,2}
	Electricity					::Dict{Tuple{Symbol,Symbol}, Array{Float64,2}}
	Charging						::Dict{Tuple{Symbol,Symbol,Int}, Float64}
	StorageLevel					::Dict{Tuple{Symbol,Symbol}, Array{Float64,2}}
	Transmission				::AxisArray{Float64,3}
	TransmissionCapacity		::AxisArray{Float64,2}
	Capacity					::Dict{Tuple{Symbol,Symbol,Symbol}, Float64}
end
