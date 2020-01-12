# Supergrid.jl

A capacity expansion model of the electricity system for arbitrary world regions, written in Julia.

## Installation

First, install the [CPLEX](https://developer.ibm.com/docloud/blog/2019/07/04/cplex-optimization-studio-for-students-and-academics/) and/or [Gurobi](https://www.gurobi.com/academia/academic-program-and-licenses/) solvers on your system and make sure that they work at the command prompt and are properly licensed. Both are free for academic use (students or faculty).

Next, type `]` to enter Julia's package mode, then:

```
(v1.3.1) pkg> add JuMP@0.18.6

(v1.3.1) pkg> add AxisArrays

(v1.3.1) pkg> add https://github.com/niclasmattsson/Supergrid
```

Grab some coffee, because installing and compiling dependencies can take quite some time to run.

## Running the model

```
julia> using Supergrid, AxisArrays

julia> r, annualelec, capac, tcapac, chart = runmodel(regionset=:Europe8, carboncap=0.1, hours=3);
```

Note that if you forget the last semicolon a **LOT** of results will get dumped to the console. Expect a long delay for precompiling the first time you run `using Supergrid`.

## Default options

```
defaultoptions() = Dict(
    :regionset => :Europe8,             # :Eurasia21, :Europe8
    :inputdatasuffix => "",             # e.g. "_landx2" to read solar input data "GISdata_solar2018_Europe8_landx2.mat"
    :runname => "",                     # change the run name without changing run parameters (e.g. if you modify the code)
    :islandindexes => [],               # superregion groupings, defaults to [1:8, 9:15, 16:21] for eurasia21, [] for europe8
    :carbontax => 0.0,                  # €/ton CO2
    :carboncap => 1.0,                  # global cap in kg CO2/kWh elec  (BAU scenario: ~0.5 kgCO2/kWh elec)
    :discountrate => 0.05,
    :maxbioenergy => 0.05,              # max share of biofuel of annual regional electricity demand (assuming CCGT, less if GT) 
    :nuclearallowed => true,
    :globalnuclearlimit => Inf,         # maximum total nuclear capacity in all regions (GW)
    :hydroinvestmentsallowed => false,
    :transmissionallowed => :all,       # :none, :islands, :all
    :hours => 1,                        # 1,2,3 or 6 hours per period
    :solarwindarea => 1,                # area multiplier for GIS solar & wind potentials
    :datayear => 2018,                  # year of the ERA5 input data (produced by GlobalEnergyGIS.jl)
    :selectdays => 1,
    :skipdays => 0,
    :solver => :cplex,
    :threads => 3,
    :showsolverlog => true,
    :rampingconstraints => false,
    :rampingcosts => false,
    :disabletechs => [],
    :disableregions => [],
    :datafolder => "",                  # Full path to GIS input data. Set to "" to use the folder in HOMEDIR/.GlobalEnergyGIS_config.
    :resultsfile => "results.jld2"      # use "" to skip saving the results in the database
)
```

## Chart options

```
julia> chart(:BARS)     # regional annual electricity generation and a separate bar chart with global totals

julia> chart(:GER)      # [or any other region name] hourly electricity generation in that region and usage of renewable resource classes

julia> chart(:TOT)      # same as previous except for global totals (aggregate of all regions)
```

## Using the results database

By default all results from model runs are saved to a database so you can reload them and produce new charts in another Julia session without having to re-run the model (to avoid saving a run, add the option `resultsfile=""` to the `runmodel()` command).

```
julia> listresults()
JLDFile C:\Stuff\Julia\results.jld2 (read-only)
 ├─� hours=3, disableregions=Symbol[:MED, :BAL, :SPA, :CEN, :GER], carboncap=0.0
 └─� hours=3, carboncap=50.0

julia> r = loadresults("hours=3, carboncap=50.0");   # copy/paste the run name *exactly* as it appears in the listing above.

julia> annualelec, capac, tcapac, chart = analyzeresults(r);

julia> chart(:BARS)
```
