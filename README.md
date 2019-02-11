# Supergrid

A capacity expansion model of the electricity system for arbitrary world regions, written in Julia 1.x.

## Installation

Type `]` to enter package mode, then:

```
(v1.1) pkg> add https://github.com/niclasmattsson/Supergrid.jl
``` 

## Running the model

```
(v1.1) pkg> activate Supergrid

(Supergrid) pkg> precompile
Precompiling project...

julia> using Supergrid, AxisArrays

julia> r, annualelec, capac, tcapac, chart = runmodel(carboncap=0.0);
```

If you forget the last semicolon a **LOT** of results will get dumped to the console.

## Default options

```
defaultoptions() = Dict(
        :carbontax => 0.0,                  # €/ton CO2
        :carboncap => 1.0,                  # global cap in kg CO2/kWh elec (BAU scenario: ~0.5 kgCO2/kWh elec)
        :maxbioenergy => 0.05,              # max share of biofuel of annual regional electricity demand (assuming CCGT, less if GT) 
        :nuclearallowed => true,
        :globalnuclearlimit => Inf,         # maximum total nuclear capacity in all regions (GW)
        :hydroinvestmentsallowed => false,
        :transmissionallowed => :all,       # :none, :islands, :all
        :hours => 1,                        # 1,2,3 or 6 hours per period
        :solarwindarea => 1,                # area multiplier for GIS solar & wind potentials
        :selectdays => 1,
        :skipdays => 0,
        :solver => :cplex,
        :threads => 3,
        :showsolverlog => true,
        :rampingconstraints => false,
        :rampingcosts => false,
        :disabletechs => [],
        :resultsfile => "results.jld2"		# use "" to skip saving the results 
    )
```

## Chart options

```
julia> chart(:BARS)

julia> chart(:GER)

julia> chart(:TOT)

```

