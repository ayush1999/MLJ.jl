module MLJ

export features, X_and_y
export SupervisedTask, UnsupervisedTask
export Supervised, Unsupervised, Deterministic, Probabilistic

# defined in include files:
export partition, @curve, @pcurve, readlibsvm        # "utilities.jl"
export rms, rmsl, rmslp1, rmsp                       # "metrics.jl"
export load_boston, load_ames, load_iris, datanow    # "datasets.jl"
export SimpleComposite                               # "composites.jl"
export Holdout, CV, Resampler                        # "resampling.jl"
export Params, params, set_params!                   # "parameters.jl"
export strange, iterator                             # "parameters.jl"
export Grid, TunedModel                              # "tuning.jl"
export ConstantRegressor, ConstantClassifier         # "builtins/Constant.jl
export KNNRegressor                                  # "builtins/KNN.jl":

# defined in include files "machines.jl" and "networks.jl":
export Machine, NodalMachine, machine
export source, node, fit!, freeze!, thaw!

# defined in include file "builtins/Transformers.jl":
export FeatureSelector
export ToIntTransformer
export UnivariateStandardizer, Standardizer
export UnivariateBoxCoxTransformer
# export OneHotEncoder
# export UnivariateBoxCoxTransformer, BoxCoxTransformer
# export DataFrameToArrayTransformer, RegressionTargetTransformer
# export MakeCategoricalsIntTransformer
# export DataFrameToStandardizedArrayTransformer
# export IntegerToInt64Transformer
# export UnivariateDiscretizer, Discretizer

# to be rexported from other packages:
export pdf, mode, median, mean

using MLJInterface
import MLJInterface

import Requires.@require  # lazy code loading package
import CategoricalArrays  # needed only for overloading index method in data.jl
import CSV
import DataFrames: DataFrame, AbstractDataFrame, SubDataFrame, eltypes, names
import Distributions: pdf, mode
import Base.==

using Query
import TableTraits

# from Standard Library:
using Statistics
using LinearAlgebra

const srcdir = dirname(@__FILE__) # the directory containing this file:


include("utilities.jl")     # general purpose utilities
include("metrics.jl")       # loss functions
include("data.jl")          # internal agnostic data interface
include("tasks.jl")         
include("datasets.jl")      # locally archived tasks for testing and demos
include("machines.jl")      # machine API
include("networks.jl")      # for building learning networks
include("composites.jl")    # composite models, incl. learning networks exported as models
include("operations.jl")    # syntactic sugar for operations (predict, transform, predict_mean, etc.)
include("resampling.jl")    # evaluating models by assorted resampling strategies
include("parameters.jl")    # hyper-parameter range constructors and nested hyper-parameter API
include("tuning.jl")        


## LOAD BUILT-IN MODELS

include("builtins/Transformers.jl")
include("builtins/Constant.jl")
include("builtins/KNN.jl")


## SETUP LAZY PKG INTERFACE LOADING (a temporary hack)

# Note: Presently an MLJ interface to a package, eg `DecisionTree`,
# is not loaded by `using MLJ` alone; one must additionally call
# `import DecisionTree`.

# files containing a pkg interface must have same name as pkg plus ".jl"

macro load_interface(pkgname, uuid::String, load_instr)
    (load_instr.head == :(=) && load_instr.args[1] == :lazy) ||
        throw(error("Invalid load instruction"))
    lazy = load_instr.args[2]
    filename = joinpath("interfaces", string(pkgname, ".jl"))

    if lazy
        quote
            @require $pkgname=$uuid include($filename)
        end
    else
        quote
            @eval include(joinpath($srcdir, $filename))
        end
    end
end

function __init__()
    @load_interface DecisionTree "7806a523-6efd-50cb-b5f6-3fa6f1930dbb" lazy=true
    @load_interface  MultivariateStats "6f286f6a-111f-5878-ab1e-185364afe411" lazy=true
end

#@load_interface XGBoost "009559a3-9522-5dbb-924b-0b6ed2b22bb9" lazy=false

end # module
