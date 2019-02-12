# Supergrid

A capacity expansion model of the electricity system for arbitrary world regions, written in Julia 1.x.

## Installation

Type `]` to enter package mode, then:

```
(v1.1) pkg> add https://github.com/niclasmattsson/Supergrid
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
        :regionset => :europe8,             # :eurasia21, :europe8
        :carbontax => 0.0,                  # €/ton CO2
        :carboncap => 1.0,                  # global cap in kg CO2/kWh elec  (BAU scenario: ~0.5 kgCO2/kWh elec)
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
        :disableregions => [],
        :islandindexes => [],               # [1:8, 9:15, 16:21] for eurasia21
        :resultsfile => "results.jld2"      # use "" to skip saving the results in the database
    )
```

## Chart options

```
julia> chart(:BARS)

julia> chart(:GER)

julia> chart(:TOT)

```

## Using the results database

```
julia> listresults()
JLDFile C:\Stuff\Julia\results.jld2 (read-only)
 ├─� hours=3, disableregions=Symbol[:MED, :BAL, :SPA, :CEN, :GER], carboncap=0.0
 └─� hours=3, carboncap=50.0

julia> r = loadresults("hours=3, carboncap=50.0");

julia> annualelec, capac, tcapac, chart = analyzeresults(r);

julia> chart(:BARS)
```