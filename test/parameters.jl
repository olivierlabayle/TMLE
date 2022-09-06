module TestParameters

using Test
using TMLE
using Distributions
using StableRNGs
using MLJModels
using MLJLinearModels
using MLJBase
using CategoricalArrays

function naive_dataset(;n=100)
    rng = StableRNG(123)
    W = rand(rng, Uniform(), n)
    T = rand(rng, [0, 1], n)
    y = 3W .+ T .+ T.*W + rand(rng, Normal(0, 0.05), n)
    return (
        y = y,
        W = W,
        T = categorical(T)
    )
end


@testset "Test counterfactual_aggregate" begin
    n=100
    dataset = naive_dataset(;n=n)
    Ψ = ATE(
        target = :y,
        treatment = (T=(case=1, control=0),),
        confounders = [:W]
    )
    η_spec = (
        Q = MLJModels.ConstantRegressor(),
        G = ConstantClassifier()
    )

    # Nuisance parameter estimation
    η = TMLE.NuisanceParameters(nothing, nothing, nothing, nothing)

    X = (W=dataset.W, T=dataset.T)
    η.H = machine(TMLE.encoder(Ψ), X)
    fit!(η.H, verbosity=0)

    η.Q = machine(η_spec.Q, MLJBase.transform(η.H, X), dataset.y)
    fit!(η.Q, verbosity=0)

    η.G = machine(η_spec.G, (W=dataset.W,), dataset.T)
    fit!(η.G, verbosity=0)

    # counterfactual_aggregate
    # The model is constant so the output is the same for all inputs
    cf_agg = TMLE.counterfactual_aggregate(Ψ, η, dataset; threshold=1e-8)
    @test cf_agg == zeros(n)

    # counterfactual_aggregate
    # The model is a linear regression
    η.Q = machine(LinearRegressor(), MLJBase.transform(η.H, X), dataset.y)
    fit!(η.Q, verbosity=0)
    X₁ = (W=dataset.W, T=categorical(ones(Int, n), levels=levels(dataset.T)))
    X₀ = (W=dataset.W, T=categorical(zeros(Int, n), levels=levels(dataset.T)))
    ŷ₁ =  predict_mean(η.Q, MLJBase.transform(η.H, X₁)) 
    ŷ₀ = predict_mean(η.Q, MLJBase.transform(η.H, X₀))
    expected_cf_agg = ŷ₁ - ŷ₀
    cf_agg = TMLE.counterfactual_aggregate(Ψ, η, dataset; threshold=1e-8)
    @test cf_agg == expected_cf_agg
    # This is the coefficient in the linear regression model
    var, coef = fitted_params(η.Q).coefs[2]
    @test var == :T__0
    @test all(coef ≈ -x for x ∈ cf_agg)

    # fluctuating
    tmle!(η, Ψ, dataset)
    cf_agg_after_fluct = TMLE.counterfactual_aggregate(Ψ, η, dataset)
    @test cf_agg_after_fluct != cf_agg
end

end

true