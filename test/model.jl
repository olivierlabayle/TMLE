module TestModel

using Test
using Tables
using TMLE
using MLJ
using StableRNGs
using StatsBase
using Distributions
using MLJBase


@testset "Test sub machines have been fitted correctly" begin
    rng = StableRNG(123)
    n = 100
    T = (t₁=categorical(sample(rng, ["CG", "CC"], Weights([0.7, 0.3]), n)),
         t₂=categorical(sample(rng, ["AT", "AA"], Weights([0.6, 0.4]), n)))
    W = (w₁=rand(rng, n), w₂=rand(rng, n))
    y = categorical(rand(rng, Bernoulli(0.3), n))
    
    query = Query((t₁="CC", t₂="AT"), (t₁="CG", t₂="AA"))
    Q̅ = ConstantClassifier()
    G = FullCategoricalJoint(ConstantClassifier())

    tmle = TMLEstimator(Q̅, G, query)

    mach = machine(tmle, T, W, y)
    fit!(mach, verbosity=0)

    # Fit outside of tmle
    Hmach = machine(OneHotEncoder(drop_last=true), T)
    fit!(Hmach, verbosity=0)
    Thot = transform(Hmach, T)
    X = merge(Thot, W)
    Q̅mach = machine(Q̅, X, y)
    fit!(Q̅mach, verbosity=0)
    @test Q̅mach.fitresult == fitted_params(mach).Q̅.target_distribution

    Gmach = machine(G, W, T)
    fit!(Gmach, verbosity=0)
    @test Gmach.fitresult == fitted_params(mach).G.fitresult
end


@testset "Test 4-points estimation and non regression" begin
    rng = StableRNG(123)
    n = 100
    T = (t₁=categorical(sample(rng, ["CG", "CC"], Weights([0.7, 0.3]), n)),
         t₂=categorical(sample(rng, ["AT", "AA", "TT"], Weights([0.5, 0.4, 0.1]), n)),
         t₃=categorical(sample(rng, ["CC", "GG", "CG"], Weights([0.6, 0.2, 0.2]), n)),
         t₄=categorical(sample(rng, ["TT", "AA"], Weights([0.6, 0.4]), n))
         )
    W = (w₁=rand(rng, n), w₂=rand(rng, n))
    y = categorical(rand(rng, Bernoulli(0.3), n))

    query = Query((t₁="CC", t₂="AT", t₃="CC", t₄="TT"), (t₁="CG", t₂="AA", t₃="GG", t₄="AA"))
    Q̅ = ConstantClassifier()
    G = FullCategoricalJoint(ConstantClassifier())
    tmle = TMLEstimator(Q̅, G, query)

    mach = machine(tmle, T, W, y)
    fit!(mach, verbosity=0)

    # Test the various api results functions

    res = briefreport(mach)[1]
    @test res.estimate ≈ -1.59 atol=1e-2
    @test res.stderror ≈ 1.32 atol=1e-2
    @test res.mean_inf_curve ≈ -1.52e-8 atol=1e-2
    @test res.pvalue ≈ 0.23 atol=1e-2
    @test res.confint[1] ≈ -4.18 atol=1e-2
    @test res.confint[2] ≈ 1.01 atol=1e-2
end


@testset "Test variables in T and Query should match" begin
    rng = StableRNG(123)
    n = 100
    T = (t₁=categorical(sample(rng, ["CG", "CC"], Weights([0.7, 0.3]), n)),
         t₂=categorical(sample(rng, ["AT", "AA"], Weights([0.6, 0.4]), n)))
    W = (w₁=rand(rng, n), w₂=rand(rng, n))
    y = categorical(rand(rng, Bernoulli(0.3), n))

    # The query ordering does not match T
    query = Query((t₂="CC", t₁="AT"), (t₂="CG", t₁="AA"))
    Q̅ = ConstantClassifier()
    G = FullCategoricalJoint(ConstantClassifier())

    tmle = TMLEstimator(Q̅, G, query)

    mach = machine(tmle, T, W, y)
    @test_throws ArgumentError fit!(mach, verbosity=0)

end

@testset "Test multiple targets with missing data" begin
    n = 100
    rng = StableRNG(123)
    T = (t=categorical(rand(rng, [0, 1], n)),)
    W = Tables.table(rand(rng, n, 2))
    Y = (
        y₁ = vcat(rand(rng, n-10), repeat([missing], 10)),
        y₂ = vcat(repeat([missing], 20), rand(rng, n-20))
    )
    query = Query((t=0,), (t=1,))
    Q̅ = MLJ.DeterministicConstantRegressor()
    G = ConstantClassifier()

    tmle = TMLEstimator(Q̅, G, query)

    mach = machine(tmle, T, W, Y)
    fit!(mach, verbosity = 0)
    
    @test length(report(mach).machines[4].data[2]) == 90
    @test length(report(mach).machines[1].data[2]) == 80
end

@testset "Test reformat" begin
    # Check column names
    T = (t₁=[1, 0, 0, 1], t₂=[1, 0, 1, 0])
    W = (w₁=[1, 2, 3, 4], t₂=[1, 2, 3, 4])
    Y = (y₁ = [1, 2, 3, 4], y₂ = [1, 2, 3, 4])

    query = Query((t₁=0, t₂=0), (t₁=1, t₂=1))
    Q̅ = MLJ.DeterministicConstantRegressor()
    G = ConstantClassifier()

    tmle = TMLEstimator(Q̅, G, query)
    ## T and W have some common column names
    @test_throws ArgumentError("T and W share some column names:[:t₂]") MLJBase.reformat(tmle, T, W, Y)
    ## Y and W have some common column names
    W = (w₁=[1, 2, 3, 4], y₂=[1, 2, 3, 4])
    @test_throws ArgumentError("W and Y share some column names:[:y₂]") MLJBase.reformat(tmle, T, W, Y)
    ## Y and T have some common column names
    Y = (y₁ = [1, 2, 3, 4], t₂ = [1, 2, 3, 4])
    @test_throws ArgumentError("T and Y share some column names:[:t₂]") MLJBase.reformat(tmle, T, W, Y)

    # Check table conversion of y
    T = (t₁=[1, 0, 0, 1], t₂=[1, 0, 1, 0])
    W = (w₁=[1, 2, 3, 4], w₂=[1, 2, 3, 4])
    Y = [1, 2, 3, 4]
    T, W, Ynew = MLJBase.reformat(tmle, T, W, Y)
    @test Ynew == (y=Y,)
    T, W, Ynew_new = MLJBase.reformat(tmle, T, W, Y)
    @test Ynew_new == Ynew

    # Check ordering of T columns and the queries
    T = (t₂=[1, 0, 0, 1], t₁=[1, 0, 1, 0])
    @test_throws ArgumentError("The variables in T and one of the queries seem to differ,"*
                               " please use the same variable names. \n Hint: The ordering in the queries and T should match.") MLJBase.reformat(tmle, T, W, Y)
end


end;

true