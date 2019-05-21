# Supergrid.jl

A capacity expansion model of the electricity system for arbitrary world regions, written in Julia 1.x.

## Installation

First, install the [CPLEX](https://ibm.onthehub.com/WebStore/ProductSearchOfferingList.aspx?srch=cplex) and/or [Gurobi](https://user.gurobi.com/download/licenses/free-academic) solvers on your system and make sure that they work at the command prompt and are properly licensed. Both are free for academic use (students or faculty).

Next, type `]` to enter Julia's package mode, then:

```
(v1.1) pkg> add JuMP@0.18.5

(v1.1) pkg> add AxisArrays

(v1.1) pkg> add https://github.com/niclasmattsson/Supergrid
```

Grab some coffee, because installing and compiling dependencies can take quite some time to run.

## Running the model

```
julia> using Supergrid, AxisArrays

julia> r, annualelec, capac, tcapac, chart = runmodel(regionset=:europe8, carboncap=0.1, hours=3);
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
        :islandindexes => [],               # Defining "superregions", e.g. use [1:8, 9:15, 16:21] for eurasia21
        :resultsfile => "results.jld2"      # use "" to skip saving the results in the database
    )
```

## Chart options

```
julia> chart(:BARS)     # regional annual electricity generation and a separate bar with global totals

julia> chart(:GER)      # [or any other region name] hourly electricity generation in that region and usage of renewable resource classes

julia> chart(:TOT)      # same as previous except for global totals (aggregate of all regions)
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