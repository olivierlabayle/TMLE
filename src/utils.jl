###############################################################################
## General Utilities
###############################################################################

function plateau!(v::AbstractVector, threshold)
    for i in eachindex(v)
        v[i] = max(v[i], threshold)
    end
end

joint_name(it) = join(it, "_&_")

joint_treatment(T) =
    categorical(joint_name.(Tables.rows(T)))


log_fit(verbosity, model) = 
    verbosity >= 1 && @info string("→ Fitting ", model)

log_no_fit(verbosity, model) =
    verbosity >= 1 && @info string("→ Reusing previous ", model)

function nomissing(table)
    sch = Tables.schema(table)
    for type in sch.types
        if nonmissingtype(type) != type
            coltable = table |> 
                       TableOperations.dropmissing |> 
                       Tables.columntable
            return NamedTuple{keys(coltable)}([disallowmissing(col) for col in coltable])
        end
    end
    return table
end

function nomissing(table, columns)
    columns = selectcols(table, columns)
    return nomissing(columns)
end

ncases(value, Ψ::Parameter) = sum(value[i] == Ψ.treatment[i].case for i in eachindex(value))

function indicator_fns(Ψ::IATE, f::Function)
    N = length(treatments(Ψ))
    indicators = Dict()
    for cf in Iterators.product((values(Ψ.treatment[T]) for T in treatments(Ψ))...)
        indicators[f(cf)] = (-1)^(N - ncases(cf, Ψ))
    end
    return indicators
end

indicator_fns(Ψ::CM, f::Function) = Dict(f(values(Ψ.treatment)) => 1)

function indicator_fns(Ψ::ATE, f::Function)
    case = []
    control = []
    for treatment in Ψ.treatment
        push!(case, treatment.case)
        push!(control, treatment.control)
    end
    return Dict(f(Tuple(case)) => 1, f(Tuple(control)) => -1)
end

function indicator_values(indicators, jointT)
    indic = zeros(Float64, nrows(jointT))
    for i in eachindex(jointT)
        val = jointT[i]
        if haskey(indicators, val)
            indic[i] = indicators[val]
        end
    end
    return indic
end

###############################################################################
## Offset & Covariate
###############################################################################

expected_value(ŷ::UnivariateFiniteVector{Multiclass{2}}) = pdf.(ŷ, levels(first(ŷ))[2])
expected_value(ŷ::AbstractVector{<:Distributions.UnivariateDistribution}) = mean.(ŷ)
expected_value(ŷ::AbstractVector{<:Real}) = ŷ

compute_offset(ŷ::UnivariateFiniteVector{Multiclass{2}}) = logit.(expected_value(ŷ))
compute_offset(ŷ::AbstractVector{<:Distributions.UnivariateDistribution}) = expected_value(ŷ)
compute_offset(ŷ::AbstractVector{<:Real}) = expected_value(ŷ)

function compute_covariate(jointT, W, Ψ, G; threshold=0.005)
    # Compute the indicator values
    indicator_fns = TMLE.indicator_fns(Ψ, TMLE.joint_name)
    indic_vals = TMLE.indicator_values(indicator_fns, jointT)
    # Compute density and truncate
    ŷ = MLJBase.predict(G, W)
    d = pdf.(ŷ, jointT)
    plateau!(d, threshold)
    indic_vals ./= d
    return indic_vals
end

###############################################################################
## Fluctuation
###############################################################################

fluctuation_input(covariate, offset) = (covariate=covariate, offset=offset)

function counterfactualTreatment(vals, T)
    Tnames = Tables.columnnames(T)
    n = nrows(T)
    NamedTuple{Tnames}(
            [categorical(repeat([vals[i]], n), levels=levels(Tables.getcolumn(T, name)))
                            for (i, name) in enumerate(Tnames)])
end



