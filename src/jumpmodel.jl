function initjumpmodel(options)
	@unpack solver, threads, showsolverlog = options
	if solver == :cplex
	# https://www.ibm.com/support/knowledgecenter/SSSA5P_12.6.0/ilog.odms.studio.help/CPLEX/ReleaseNotes/topics/releasenotes126/newParameterNames.html
	# https://www.ibm.com/support/knowledgecenter/SSSA5P_12.8.0/ilog.odms.cplex.help/CPLEX/Parameters/topics/introListAlpha.html
	# https://www.ibm.com/support/knowledgecenter/SSSA5P_12.8.0/ilog.odms.cplex.help/CPLEX/UsrMan/topics/cont_optim/barrier/19_tuning_title_synopsis.html
		m = Model(solver=CplexSolver(CPXPARAM_LPMethod=4, CPXPARAM_Threads=threads, CPXPARAM_Read_Scale=1,
					CPXPARAM_Preprocessing_Dual=-1, CPXPARAM_Barrier_Crossover=-1, CPXPARAM_Emphasis_Numerical=1,
					CPXPARAM_ScreenOutput=Int(showsolverlog)))
					# CPXPARAM_Barrier_ConvergeTol=1e-8 (default), CPXPARAM_Barrier_Display=2,
					# CPXPARAM_Barrier_Crossover=-1 or 2, CPXPARAM_Emphasis_Memory=1,
					# Tom: CPXPARAM_Barrier_ColNonzeros=200, CPXPARAM_Preprocessing_Fill=0 (doesn't help)

	elseif solver == :gurobi
		m = Model(solver=GurobiSolver(Method=2, Threads=threads, NumericFocus=2, ScaleFlag=3, Crossover=0))
					# OptimalityTol=1e-9, FeasibilityTol=1e-9, NumericFocus=0-3, ScaleFlag=-1-3, Crossover=0
	elseif solver == :glpk
		m = Model(solver=GLPKSolverLP(method=:InteriorPoint, msg_lev=GLPK.MSG_ON))
	elseif solver == :clp
		m = Model(solver=ClpSolver(SolveType=4, LogLevel=4))
	else
		println("No solver installed called $solver.")
	end
	return m
end

function makevariables(m, sets)
	@unpack REGION, FUEL, TECH, CLASS, STORAGECLASS, HOUR, techtype = sets

	@variables m begin
		Systemcost[r in REGION]															# M€/year
		CO2emissions[r in REGION]														# kton CO2/year
		FuelUse[r in REGION, f in FUEL]	>= 0											# GWh fuel/year
		Electricity[r in REGION, k in TECH, c in CLASS[k], h in HOUR] >= 0				# GWh elec/period
		AnnualGeneration[r in REGION, k in TECH] >= 0									# GWh elec/year
		Charging[r in REGION, k in TECH, h in HOUR; techtype[k] == :storage] >= 0		# GWh elec/period (electricity used to charge)
		StorageLevel[r in REGION, k in TECH, c in STORAGECLASS[k], h in HOUR; techtype[k] == :storage] >= 0	 # TWh elec (in storage)
		Transmission[r1 in REGION, r2 in REGION, h in HOUR] >= 0						# GWh elec/period
		TransmissionCapacity[r1 in REGION, r2 in REGION] >= 0							# GW elec
		Capacity[r in REGION, k in TECH, c in CLASS[k]] >= 0							# GW elec
	end #variables

	return Vars(Systemcost, CO2emissions, FuelUse, Electricity, AnnualGeneration, Charging, StorageLevel,
					Transmission, TransmissionCapacity, Capacity)
end

function setbounds(sets, params, vars, options)
	@unpack REGION, TECH, CLASS, techtype = sets
	@unpack Capacity, TransmissionCapacity = vars
	@unpack classlimits, hydrocapacity, transmissionislands, demand = params
	@unpack hydroinvestmentsallowed, nuclearallowed, transmissionallowed, disabletechs = options
	for r in REGION, k in TECH
		if techtype[k] == :vre || k == :csp
			for c in CLASS[k]
				setupperbound(Capacity[r,k,c], classlimits[r,k,c])
			end
		end
	end
	for r in REGION
		setlowerbound(Capacity[r,:hydro,:x0], hydrocapacity[r,:x0])
		for c in CLASS[:hydro]
			if hydroinvestmentsallowed
				setupperbound(Capacity[r,:hydro,c], hydrocapacity[r,c])
			else
				setupperbound(Capacity[r,:hydro,c], c == :x0 ? hydrocapacity[r,c] : 0.0)
			end
		end
	end
	if !nuclearallowed
		for r in REGION
			setupperbound(Capacity[r,:nuclear,:_], 0.0)
		end
	end
	for r1 in REGION, r2 in REGION
		if transmissionallowed == :none || (transmissionallowed == :islands && !transmissionislands[r1,r2])
			setupperbound(TransmissionCapacity[r1,r2], 0.0)
		end
	end
	for r in REGION, k in disabletechs, c in CLASS[k]
		setupperbound(Capacity[r,k,c], 0.0)
	end
	# for r in REGION
	# 	setupperbound(AnnualGeneration[r,:csp], 0.50 * sum(demand[r,h] for h in HOUR) * hoursperperiod)
	# end
end

function makeconstraints(m, sets, params, vars, hourinfo, options)
	@unpack REGION, FUEL, TECH, CLASS, STORAGECLASS, HOUR, techtype, techfuel, reservoirclass = sets
	@unpack cf, transmissionlosses, demand, cfhydroinflow, efficiency, rampingrate, dischargetime, initialstoragelevel,
			minflow_existinghydro, emissionsCO2, fuelcost, variablecost, smalltransmissionpenalty, investcost, crf, fixedcost,
			transmissioninvestcost, transmissionfixedcost, hydroeleccost = params
	@unpack Systemcost, CO2emissions, FuelUse, Electricity, AnnualGeneration, Charging, StorageLevel,
			Transmission, TransmissionCapacity, Capacity = vars
	@unpack hoursperperiod = hourinfo
	@unpack carbontax, carboncap, rampingconstraints, maxbioenergy, globalnuclearlimit = options

	@constraints m begin
		ElecCapacity[r in REGION, k in TECH, c in CLASS[k], h in HOUR],
			Electricity[r,k,c,h] <= Capacity[r,k,c] * (k == :csp ? 1 : cf[r,k,c,h]) * hoursperperiod

		ElecDemand[r in REGION, h in HOUR],
			sum(Electricity[r,k,c,h] for k in TECH, c in CLASS[k]) - sum(Charging[r,k,h] for k in TECH if techtype[k] == :storage) +
				+ sum((1-transmissionlosses[r2,r])*Transmission[r2,r,h] - Transmission[r,r2,h] for r2 in REGION) >=
					demand[r,h] * hoursperperiod

		# <= instead of == to avoid need of slack variable to deal with spillage during spring floods, etc
		StorageBalance[r in REGION, k in TECH, sc in STORAGECLASS[k], h in HOUR; techtype[k] == :storage],
			(StorageLevel[r,k,sc,h] - StorageLevel[r,k,sc, (h>1) ? h-1 : length(HOUR)]) / 1 <=  # unit: energy diff per period (TWh/period)
				0.001 * Charging[r,k,h] +
				+ (k == :hydro ? 0.001 * hoursperperiod * sum(cfhydroinflow[r,c,h] * Capacity[r,:hydro,c] for c in reservoirclass[sc])
								: 0.0) +
				+ (k == :csp ? 0.001 * hoursperperiod * sum(cf[r,:csp,c,h] * Capacity[r,:csp,c] for c in reservoirclass[sc])
								: 0.0) +
				- 0.001 * sum(Electricity[r,k,c,h]/efficiency[k] for c in reservoirclass[sc])

		MaxStorageCapacity[r in REGION, k in TECH, sc in STORAGECLASS[k], h in HOUR; techtype[k] == :storage],
			StorageLevel[r,k,sc,h] <= sum(Capacity[r,k,c] * dischargetime[r,k,c] for c in reservoirclass[sc]) / 1000

		InitialStorageLevel[r in REGION, k in TECH, sc in STORAGECLASS[k]; techtype[k] == :storage],
			StorageLevel[r,k,sc,1] ==
				initialstoragelevel * sum(Capacity[r,k,c] * dischargetime[r,k,c] for c in reservoirclass[sc]) / 1000

		# consider turbine efficiencies later
		MinHydroFlow[r in REGION, h in HOUR],
			Electricity[r,:hydro,:x0,h] >= minflow_existinghydro * hoursperperiod * cfhydroinflow[r,:x0,h] * Capacity[r,:hydro,:x0]

		# We'll add pumped hydro later
		NoCharging[r in REGION, h in HOUR, k in [:hydro, :csp]],
			Charging[r,k,h] == 0

		ChargingNeedsBattery[r in REGION, h in HOUR],
			Charging[r,:battery,h] <= Capacity[r,:battery, :_] * hoursperperiod

		MaxTransmissionCapacity[r1 in REGION, r2 in REGION, h in HOUR],
			Transmission[r1,r2,h] <= TransmissionCapacity[r1,r2] * hoursperperiod

		TwoWayStreet[r1 in REGION, r2 in REGION],
			TransmissionCapacity[r1,r2] == TransmissionCapacity[r2,r1] 

		NoTransmission[r1 in REGION, r2 in REGION; transmissioninvestcost[r1,r2] == 0],
			TransmissionCapacity[r1,r2] == 0

		Calculate_AnnualGeneration[r in REGION, k in TECH],
			AnnualGeneration[r,k] == sum(Electricity[r,k,c,h] for c in CLASS[k], h in HOUR)

		Calculate_FuelUse[r in REGION, f in FUEL; f != :_],
			FuelUse[r,f] == sum(AnnualGeneration[r,k]/efficiency[k] for k in TECH if techfuel[k]==f)

		BioLimit[r in REGION],
			sum(AnnualGeneration[r,k] for k in [:bioGT, :bioCCGT]) <= maxbioenergy * sum(demand[r,h] for h in HOUR) * hoursperperiod

		TotalCO2[r in REGION],
			CO2emissions[r] == sum(FuelUse[r,f] * emissionsCO2[f] for f in FUEL)

		GlobalCO2Cap,
			sum(CO2emissions[r] for r in REGION) <= carboncap * sum(demand) * hoursperperiod

		# Storage costs included in ordinary Capacity costs
		# Transmission costs halved since they are counted twice (allocate half the cost to sending and receiving regions)
		# make this regional later
		Totalcosts[r in REGION],
			Systemcost[r] ==
				0.001 * sum(FuelUse[r,f] * fuelcost[f] for f in FUEL) +
				+ 0.001 * carbontax * CO2emissions[r] +
				+ 0.001 * sum(Electricity[r,k,c,h] * variablecost[k] for k in TECH, c in CLASS[k], h in HOUR) +
				+ 0.001 * sum(Electricity[r,:hydro,c,h] * hydroeleccost[r,c] for c in CLASS[:hydro], h in HOUR) +
				+ 0.001 * sum(Transmission[r,r2,h] * smalltransmissionpenalty for r2 in REGION, h in HOUR) +
				+ sum(Capacity[r,k,c] * (investcost[k,c] * crf[k] + fixedcost[k]) for k in TECH, c in CLASS[k]) +
				+ 0.5 * sum(TransmissionCapacity[r,r2] *
							(transmissioninvestcost[r,r2] * crf[:transmission] + transmissionfixedcost[r,r2]) for r2 in REGION)
		# =#
	end	#constraints

	if rampingconstraints
		@constraints m begin
			RampingDown[r in REGION, k in TECH, c in CLASS[k], h in HOUR; rampingrate[k] < 1],
				Electricity[r,k,c,h] - Electricity[r,k,c, (h>1) ? h-1 : length(HOUR)] >=
					-rampingrate[k] * Capacity[r,k,c] * cf[r,k,c,h] * hoursperperiod

			RampingUp[r in REGION, k in TECH, c in CLASS[k], h in HOUR; rampingrate[k] < 1],
				Electricity[r,k,c,h] - Electricity[r,k,c, (h>1) ? h-1 : length(HOUR)] <=
					rampingrate[k] * Capacity[r,k,c] * cf[r,k,c,h] * hoursperperiod
		end
	else
		RampingDown = RampingUp = nothing
	end

	if globalnuclearlimit != Inf
		@constraints m begin
			NuclearCapacityLimit,
				sum(Capacity[r,:nuclear,:_] for r in REGION) <= globalnuclearlimit
		end
	end

	return Constraints(ElecCapacity, ElecDemand, RampingDown, RampingUp, StorageBalance, MaxStorageCapacity, InitialStorageLevel,
				MaxTransmissionCapacity, TwoWayStreet, NoTransmission, NoCharging, ChargingNeedsBattery,
				Calculate_AnnualGeneration, Calculate_FuelUse, TotalCO2, Totalcosts)
end

function makeobjective(m, sets, vars)
	@unpack REGION = sets
	@unpack Systemcost = vars

	@objective m Min begin
		sum(Systemcost[r] for r in REGION)
	end
end
