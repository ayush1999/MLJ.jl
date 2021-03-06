abstract type AbstractTrainableModel <: MLJType end

mutable struct TrainableModel{B<:Model} <: AbstractTrainableModel

    model::B
    fitresult
    cache
    args::Tuple
    report
    rows # remember last rows used for convenience
    
    function TrainableModel{B}(model::B, args...) where B<:Model

        # check number of arguments for model subtypes:
        !(B <: Supervised) || length(args) == 2 ||
            throw(error("Wrong number of arguments. "*
                        "Use NodalTrainableModel(model, X, y) for supervised learner models."))
        !(B <: Unsupervised) || length(args) == 1 ||
            throw(error("Wrong number of arguments. "*
                        "Use NodalTrainableModel(model, X) for an unsupervised learner model."))
        
        trainable_model = new{B}(model)
        trainable_model.args = args
        trainable_model.report = Dict{Symbol,Any}()

        return trainable_model

    end
end

# automatically detect type parameter:
TrainableModel(model::B, args...) where B<:Model = TrainableModel{B}(model, args...)

# constructor for tasks instead of bare data:
TrainableModel(model::Model, task::SupervisedTask) = TrainableModel(model, X_and_y(task)...)
TrainableModel(model::Model, task::UnsupervisedTask) = TrainableModel(model, task.data)

function fit!(trainable_model::TrainableModel; rows=nothing, verbosity=1)

    verbosity < 1 || @info "Training $trainable_model whose model is $(trainable_model.model)."

    if !isdefined(trainable_model, :fitresult)
        if rows == nothing
            rows = (:) # error("An untrained TrainableModel requires rows to fit.")
        end
        args = [arg[Rows, rows] for arg in trainable_model.args]
        trainable_model.fitresult, trainable_model.cache, report =
            fit(trainable_model.model, verbosity, args...)
        trainable_model.rows = rows
    else
        if rows == nothing # (ie rows not specified) update:
            args = [arg[Rows, trainable_model.rows] for arg in trainable_model.args]
            trainable_model.fitresult, trainable_model.cache, report =
                update(trainable_model.model, verbosity, trainable_model.fitresult,
                       trainable_model.cache, args...)
        else # retrain from scratch:
            args = [arg[Rows, rows] for arg in trainable_model.args]
            trainable_model.fitresult, trainable_model.cache, report =
                fit(trainable_model.model, verbosity, args...)
            trainable_model.rows = rows
        end
    end

    if report != nothing
        merge!(trainable_model.report, report)
    end

    return trainable_model

end

trainable(model::Model, args...) = TrainableModel(model, args...)


