function makedispatchvariables(m, sets)
    @unpack REGION, FUEL, TECH, CLASS, STORAGECLASS, HOUR, techtype = sets

    storagetechs = [k for k in TECH if techtype[k] == :storage]

    @variables m begin
        Systemcost[r in REGION]                                                         # M€/year
        CO2emissions[r in REGION]                                                       # kton CO2/year
        FuelUse[r in REGION, f in FUEL] >= 0                                            # GWh fuel/year
        Electricity[r in REGION, k in TECH, c in CLASS[k], h in HOUR] >= 0              # GWh elec/period
        AnnualGeneration[r in REGION, k in TECH] >= 0                                   # GWh elec/year
        Charging[r in REGION, k in storagetechs, h in HOUR] >= 0       # GWh elec/period (electricity used to charge)
        StorageLevel[r in REGION, k in storagetechs, c in STORAGECLASS[k], h in HOUR] >= 0  # TWh elec (in storage)
        Transmission[r1 in REGION, r2 in REGION, h in HOUR] >= 0                        # GWh elec/period
    end #variables

    dummy = Model()
    @variables dummy begin
        TransmissionCapacity[r1 in REGION, r2 in REGION] >= 0                           # GW elec
        Capacity[r in REGION, k in TECH, c in CLASS[k]] >= 0                            # GW elec
        SolarCapacity[r in REGION, k in [:pv, :csp], pv in CLASS[:pv], csp in CLASS[:csp]] >= 0     # GW elec
    end #variables

    return Vars(Systemcost, CO2emissions, FuelUse, Electricity, AnnualGeneration, Charging, StorageLevel,
                    Transmission, TransmissionCapacity, Capacity, SolarCapacity)
end

function setdispatchbounds(capacity, transmissioncapacity, sets, params, vars, hourinfo, options)
    @unpack REGION, TECH, CLASS, HOUR, STORAGECLASS, reservoirclass, techtype = sets
    @unpack Electricity, StorageLevel, Charging, Transmission = vars
    @unpack cf, dischargetime, initialstoragelevel, minflow_existinghydro, cfhydroinflow = params
    @unpack hoursperperiod = hourinfo

    storagetechs = [k for k in TECH if techtype[k] == :storage]

    for r in REGION, k in TECH, c in CLASS[k], h in HOUR
        setupperbound(Electricity[r,k,c,h],
            capacity[r,k,c] * (k == :csp ? 1 : cf[r,k,c,h]) * hoursperperiod)
    end
    for r in REGION, k in storagetechs, sc in STORAGECLASS[k], h in HOUR
        setupperbound(StorageLevel[r,k,sc,h],
            sum(capacity[r,k,c] * dischargetime[r,k,c] for c in reservoirclass[sc]) / 1000)
    end
    for r in REGION, k in storagetechs, sc in STORAGECLASS[k]
        setupperbound(StorageLevel[r,k,sc,1], initialstoragelevel *
                sum(capacity[r,k,c] * dischargetime[r,k,c] for c in reservoirclass[sc]) / 1000)
        setlowerbound(StorageLevel[r,k,sc,1], initialstoragelevel *
                sum(capacity[r,k,c] * dischargetime[r,k,c] for c in reservoirclass[sc]) / 1000)
    end
    for r in REGION, h in HOUR
        setlowerbound(Electricity[r,:hydro,:x0,h],
            minflow_existinghydro * hoursperperiod * cfhydroinflow[r,:x0,h] * capacity[r,:hydro,:x0])
        setupperbound(Charging[r,:battery,h], capacity[r,:battery, :_] * hoursperperiod)
    end
    for r in REGION, h in HOUR, k in [:hydro, :csp]
        setupperbound(Charging[r,k,h], 0)
        setlowerbound(Charging[r,k,h], 0)
    end
    for r1 in REGION, r2 in REGION, h in HOUR
        setupperbound(Transmission[r1,r2,h], transmissioncapacity[r1,r2] * hoursperperiod)
    end
end

function makedispatchconstraints(capacity, transmissioncapacity, m, sets, params, vars, hourinfo, options)
    @unpack REGION, FUEL, TECH, CLASS, STORAGECLASS, HOUR, techtype, techfuel, reservoirclass = sets
    @unpack cf, transmissionlosses, demand, cfhydroinflow, efficiency, rampingrate,
            emissionsCO2, fuelcost, variablecost, smalltransmissionpenalty, investcost, crf, fixedcost,
            transmissioninvestcost, transmissionfixedcost, hydroeleccost = params
    @unpack Systemcost, CO2emissions, FuelUse, Electricity, AnnualGeneration, Charging, StorageLevel,
            Transmission = vars
    @unpack hoursperperiod = hourinfo
    @unpack carbontax, carboncap, rampingconstraints, maxbioenergy = options

    storagetechs = [k for k in TECH if techtype[k] == :storage]

    @constraints m begin
        ElecDemand[r in REGION, h in HOUR],
            sum(Electricity[r,k,c,h] for k in TECH, c in CLASS[k]) - sum(Charging[r,k,h] for k in TECH if techtype[k] == :storage) +
                + sum((1-transmissionlosses[r2,r])*Transmission[r2,r,h] - Transmission[r,r2,h] for r2 in REGION) >=
                    demand[r,h] * hoursperperiod

        # <= instead of == to avoid need of slack variable to deal with spillage during spring floods, etc
        StorageBalance[r in REGION, k in storagetechs, sc in STORAGECLASS[k], h in HOUR],
            (StorageLevel[r,k,sc,h] - StorageLevel[r,k,sc, (h>1) ? h-1 : length(HOUR)]) / 1 <=  # unit: energy diff per period (TWh/period)
                0.001 * Charging[r,k,h] +
                + (k == :hydro ? 0.001 * hoursperperiod * sum(cfhydroinflow[r,c,h] * capacity[r,:hydro,c] for c in reservoirclass[sc])
                                : 0.0) +
                + (k == :csp ? 0.001 * hoursperperiod * sum(cf[r,:csp,c,h] * capacity[r,:csp,c] for c in reservoirclass[sc])
                                : 0.0) +
                - 0.001 * sum(Electricity[r,k,c,h]/efficiency[k] for c in reservoirclass[sc])

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
                + sum(capacity[r,k,c] * (investcost[k,c] * crf[k] + fixedcost[k]) for k in TECH, c in CLASS[k]) +
                + 0.5 * sum(transmissioncapacity[r,r2] *
                            (transmissioninvestcost[r,r2] * crf[:transmission] + transmissionfixedcost[r,r2]) for r2 in REGION)
        # =#
    end #constraints

    if rampingconstraints
        @constraints m begin
            RampingDown[r in REGION, k in TECH, c in CLASS[k], h in HOUR; rampingrate[k] < 1],
                Electricity[r,k,c,h] - Electricity[r,k,c, (h>1) ? h-1 : length(HOUR)] >=
                    -rampingrate[k] * capacity[r,k,c] * cf[r,k,c,h] * hoursperperiod

            RampingUp[r in REGION, k in TECH, c in CLASS[k], h in HOUR; rampingrate[k] < 1],
                Electricity[r,k,c,h] - Electricity[r,k,c, (h>1) ? h-1 : length(HOUR)] <=
                    rampingrate[k] * capacity[r,k,c] * cf[r,k,c,h] * hoursperperiod
        end
    else
        RampingDown = RampingUp = nothing
    end

    return Constraints(nothing, ElecDemand, RampingDown, RampingUp, StorageBalance, nothing, nothing,
                nothing, nothing, nothing, nothing, nothing,
                Calculate_AnnualGeneration, Calculate_FuelUse, TotalCO2, Totalcosts)
end
