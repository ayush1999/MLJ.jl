## Rough outline of the learning networks API

The API detailed here is probably not intended for the beginner user
but allows advanced users and MLJ developers to build composite models
of a fairly general variety (e.g., learners wrapped in transformations,
models for resampling, stacked models, etc). "Prefabricated" composite
learners can be then be exposed to the general user (see the example
under "goals" below).

This document assumes familiarity with the
[glossary](https://github.com/alan-turing-institute/MLJ.jl/blob/master/doc/glossary.md)
but also elucidates it. The source code is [here](https://github.com/alan-turing-institute/MLJ.jl/blob/master/src/networks.jl).


Recall that the `Model`
[API](https://github.com/alan-turing-institute/MLJ.jl/blob/master/doc/adding_new_models.md)
specifies that each model has `fit` and `update` methods, called like
this:

````julia
fitresult, cache, report = fit(model::Model, verbosity, X, y)
````

and

````julia
fitresult, cache, report = update(model::Model, verbosity, old_fitresult, old_cache, X, y)
````

### goals

As an elementary goal of an API for learning networks we would like to
have composite models like this:

````julia
import MLJ: Supervised, Transformer

mutable struct WetSupervised{L<:Supervised,TX<:Transformer,Ty<:Transformer} 
    learner::L
    transformer_X::TX
    transformer_y::Ty
end
````

When we call `fit` on this composite learner, we want it to fit a
transformer to the inputs using `transformer_X`, fit a transformer to
the target, using `transformer_y`, and fit the "dry" `learner` using the
transformed data. When we dispatch `predict` on the `fitresult` of
this training, predictions should be automatically
inverse-transformed. Finally, when we call `update` on the
`fitresult` then *only the necessary component models ought to be
retrained.* In particular, if transformer hyperparameters are not
changed, then only the learner is retrained.

Other possible use cases are composite models that resample a model for
cross-validation and stacked models with a meta-learner.


### source nodes

````julia
abstract type Node <: MLJType end

mutable struct SourceNode{D} 
    data::D 
end 
````

A source node `X` is callable, with this behaviour: `X() = X.data`
(usually training data) and `X(Xnew) = Xnew`.

Learning networks are defined by `LearningNode`s. Inside each
`LearningNode` is a `TrainableModel` and the definitions of the two
types are coupled.

We presently constrain each connected component of a learning network
(as defined by the normal flow of information, with no account paid to
training) to have a unique source node, although the network may have
several connected components coupled via *training* connections.

Like `SourceNodes`, `LearningNode`s will be callable. If `X` is a
`LearningNode` then `X()` is the result of applying the complete
learning network, up to node `X`, to the data at the source of
`X`. Meanwhile, `X(Xnew)` refers to the the result one would obtain if
the data at the source of `X` were to be replaced with `Xnew`.


### trainable models

````julia
mutable struct TrainableModel{M<:Model}
    model::M
    fitresult
    cache
    args::Vector{Node}
    report
    tape::Vector{TrainableModel}
    frozen::Bool
end
````

Elements of `args` (the *training arguments*) can be `SourceNode`s or
`LearningNode`s, which have the common supertype `Node`. We have a constructor,

````julia 
trainable(model::Model, args::Node...)
````
 
which computes its dependency `tape`, and sets `frozen=false`, and
leaves other fields undefined.  Methods `freeze!(::TrainableModel)`
and `thaw!(::TrainableModel)` reset the `frozen` flag accordingly.

````julia
fit!(trainable::TrainableModel, verbosity; kwargs...)
fit!(trainable::TrainableModel; kwargs...)
````

Computes or updates the `fitresult` field in `TrainableModel` (as well
as `cache`) by calling `fit` or `update` on its model (with the
specified `kwargs` if any). To obtain our training data we reach back
to the source nodes of each argument. The method throws an error if
any other trainable model on which `trainable` depends has not itself
been trained yet. (The responsibility for scheduling lies not with a
trainable model but with the learning nodes that point to them.) If no
`verbosity` is specified, a default of `1` is used.

> **Implementation detail:** The data arguments provided the
> (low-level) model `fit` method are `[arg() for arg in args]...`.

For each operation supported by a model `M` (e.g, `predict`,
`inverse_transform`) the learning networkds API defines a
corresponding operation for a `TrainableModel{M}` object. So, for
example:

````julia
predict(trainable::TrainableModel{M<:Supervised}, Xnew) = 
    predict(trainable.model, trainable.fitresult, Xnew)
````
and

````julia
inverse_transform(trainable::TrainableModel{T<:Transformer}, Xnew) = 
    inverse_transform(trainable.model, trainable.fitrestult, Xnew)
````

where `Xnew` is just data. 


### learning nodes

Recall from the
[glossary](https://github.com/alan-turing-institute/MLJ.jl/blob/master/doc/glossary.md)
that the *arguments* of a learning node are other nodes (source or
learning) indicating its upstream connections; these constitute its
`args` field (internal constructor omitted):

````julia
struct LearningNode{M<:Union{TrainableModel, Nothing}} <: Node

    operation::Function   # that can be dispatched on `trainable`(eg, `predict`) or a static operation
    trainable::M          # is `nothing` for static operations
    args                  # nodes where `operation` looks for its arguments
    tape::Vector{TrainableModel}    # for tracking dependencies
    depth::Int64       

end
````

The dependency `tape` (e.g., a DAG of trainable models) is computed on
construction, by merging the `tape`s of its `args` and incorporating the new
trainable model `trainable`:

````julia
LearningNode(operation, trainable::TrainableModel, args::Node...)`
LearningNode(operation, args::Node...) = LearningNode(operation, nothing, args::Node...)
````

We make each learning node `z` callable: `z(Xnew)` is the result of
applying the operations of the complete learning network, up to node
`z`, to the source node of `X`, as if the contents of the source node
were replaced by `Xnew`. 

> **implementation detail:** We recursively define `z(Xnew) =
> z.operation(z.trainable, args[1](Xnew), args[2](Xnew), ...,
> args[k](Xnew)`), remembering that if `arg` is a source node, then
> `arg(Xnew)=Xnew`.

We furthermore introduce the following additional syntax, in the case that 
`trainable` is a `Trainable{<:Supervised}` object:

````julia
predict(trainable::TrainableModel, X::Union{LearningNode,Source}) =
    LearningNode(predict, trainable, X)
````

This extends syntax introduced above, where `X` was just data and the
return value new data.  (Similar syntax is introduced to the
`transform` and `inverse_transform` methods of `Transformer`
models). 

If, for example, `X` is a learning node, then the binding

````julia
yhat = predict(trainable, X)
````

means 

````julia
yhat(Xnew) == predict(trainable.model, trainable.fitresult, X(Xnew))
````

What `X(Xnew)` means depends, in turn, on whether `X` is another
learning node, or a source node. Recall that in the source node case
`X(Xnew) = Xnew`. 

If `X` is just data, then `yhat=predict(trainable, X)` falls back to
have its earlier meaning, so that `yhat` is also just data.

````
function fit!(X::LearningNode, verbosity; kwargs...)
function fit!(X::LearningNode; kwargs...)
````

Call `fit!` on all trainable models in the dependency `tape` of `X` in
an appropriate order (in the future using a scheduler) unless a
trainable model has been previously fit and is frozen. The `kwargs`
are passed to the the `fit!` call to `X.trainable` only. For data, use
what is currently located at each source node on which the learning
node depends. Remember, that for training purposes, multiple sources
are possible (our use case below being a case in point). No
specification of `verbosity` implies a default of `1`.
    
	
### example

We can now give an implementation of the `WetSupervised` model
described in "goals" above. We start by defining a cache type for our
composite model.


````julia
import LearningNode, TrainableModel, fit, predict

# 1st three fields for each component's trainable model; 2nd three
# fields for copies of corresponding models (hyperparameters) used in last training:
mutable struct WetSupervisedCache{L,TX,Ty} <: MLJType
    t_X::TrainableModel{TX}   
    t_y::TrainableModel{Ty}
    l::TrainableModel{L}
    transformer_X::TX      
    transformer_y::Ty
    learner::L
end

function fit(composite::WetSupervised, verbosity, Xtrain, ytrain)

    X = node(Xtrain) # instantiates a source node
    y = node(ytrain)
    
    t_X = trainable(composite.transformer_X, X)
    t_y = trainable(composite.transformer_y, y)

    Xt = array(transform(t_X, X))
    yt = transform(t_y, y)

    l = trainable(composite.learner, Xt, yt)
    zhat = predict(l, Xt)

    yhat = inverse_transform(t_y, zhat)
    fit!(yhat, verbosity-1)

    fitresult = yhat
    report = l.report
    cache = WetSupervisedCache(t_X, t_y, l,
                               deepcopy(composite.transformer_X),
                               deepcopy(composite.transformer_y),
                               deepcopy(composite.learner))

    return fitresult, cache, report

end

function update(composite::WetSupervised, verbosity, old_fitresult, old_cache, X, y; kwargs...)

    t_X, t_y, l = old_cache.t_X, old_cache.t_y, old_cache.l
    transformer_X, transformer_y = old_cache.transformer_X, old_cache.transformer_y
    learner = old_cache.learner 

    case1 = (composite.transformer_X == transformer_X) # true if `transformer_X` has not changed
    case2 = (composite.transformer_y == transformer_y) # true if `transformer_y` has not changed
    case3 = (composite.learner == learner) # true if `learner` has not changed

    # we initially activate all trainable models, but leave them in the
    # state needed for this call to update (for post-train inspection):
    thaw!(t_X); thaw!(t_y); thaw!(l)
    
    if case1
        freeze!(t_X)
    end
    if case2
        freeze!(t_y)
    end
    if case1 && case2 && case3
        freeze!(l)
    end

    fit!(old_fitresult, verbosity-1; kwargs...)
	
    old_cache.transformer_X = deepcopy(composite.transformer_X)
    old_cache.transformer_y = deepcopy(composite.transformer_y)
    old_cache.learner = copy(composite.learner)
	
    return old_fitresult, old_cache, l.report

end

predict(composite::WetSupervised, fitresult, Xnew) = fitresult(Xnew)
````        




