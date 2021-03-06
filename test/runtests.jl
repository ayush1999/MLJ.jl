# It is suggested that test code for MLJ.jl include files be placed in
# a file of the same name under "test/" (and included below) and that
# this test code be wrapped in a module. Any new module name will do -
# eg, `module TestDatasets` for code testing `datasets.jl`.

using MLJ
# using Revise
using Test

@constant junk=KNNRegressor()
properties(KNNRegressor)
operations(KNNRegressor)
type_of_X(KNNRegressor)
type_of_y(KNNRegressor)

include("metrics.jl")
include("datasets.jl")
include("KNN.jl")
include("networks.jl")
include("Transformers.jl")
include("DecisionTree.jl")


