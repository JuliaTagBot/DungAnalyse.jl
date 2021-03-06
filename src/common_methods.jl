using Unitful, Statistics, StaticArrays, Interpolations, StructArrays

const Point = SVector{2, Float64}
point(x::Missing) = missing
point(x::AbstractVector{Float64}) = Point(x[1], x[2])
points(x::Matrix{Float64}) = point.(eachrow(x))
point(x::Instantaneous{Matrix{Float64}})= point(vec(x.data))
# point(x) = point(x[])
struct Track
    coords::Vector{Point}
    distance::Vector{Float64}
    direction::Vector{Float64}
    tp::Int
    Δt::Float64
end
function Track(x::Prolonged{Matrix{Float64}})
    xyt = !issorted(x.data[:,3]) ? sortslices(x.data, dims=1, lt=(x,y)->isless(x[3],y[3])) : x.data
    t = xyt[:,3]
    Δ = diff(t)
    δ = minimum(Δ)
    xy = points(xyt)
    n = length(xy)
    if !all(x -> isapprox(x, δ, atol = 1/30), Δ)
        itp = interpolate((t, ), xy, Gridded(Linear()))
        t_lin = range(t[1], t[end], length = n)
        δ = step(t_lin)
        xy .= itp.(t_lin)
    end
    _xy, v, a, m = smoothed(xy)
    xy .= Point.(eachcol(_xy))
    tp = findfirst(x -> x > 0.5, m)
    if tp ≡ nothing || tp ≥ n - 1
        tp = n
    end
    Track(xy, v, a, tp, δ)
end
struct TimedPoint
    xy::Point
    t::Float64
end
const PointCollection = StructVector{TimedPoint}
pointcollection(x::Missing, t₀) = StructVector{TimedPoint}(undef, 0)
pointcollection(x, t₀) = StructVector(TimedPoint(Point(i[1], i[2]), i[3] - t₀) for i in eachrow(x.data))
function getdata(x)
    feeder = point(x[:feeder])
    track = Track(x[:track])
    pellet = pointcollection(get(x, :pellet, missing), x[:track].data[1,3])
    feeder, track, pellet
end
abstract type DungMethod end
struct ClosedNest <: DungMethod 
    feeder::Point
    nest::Point
    track::Track
    pellet::PointCollection
end
function ClosedNest(x) 
    feeder, track, pellet = getdata(x.data)
    nest = point(x.data[:nest])
    ClosedNest(feeder, nest, track, pellet)
end
struct Transfer <: DungMethod
    feeder::Point
    track::Track
    pellet::PointCollection
    south::Point
    north::Point
    nest2feeder::Float64
    azimuth::Float64
end
function Transfer(x) 
    feeder, track, pellet = getdata(x.data)
    south = point(x.data[:south])
    north = point(x.data[:north])
    d, u = split(string(x.metadata.setup[:nest2feeder]))
    nest2feeder = Float64(ustrip(uconvert(Unitful.cm, parse(Int, d)*getfield(Unitful, Symbol(u)))))
    d, u = split(string(x.metadata.setup[:azimuth]))
    azimuth = Float64(ustrip(uconvert(Unitful.rad, parse(Int, d)*getfield(Unitful, Symbol(u)))))
    Transfer(feeder, track, pellet, south, north, nest2feeder, azimuth)
end
struct TransferNest <: DungMethod
    feeder::Point
    track::Track
    pellet::PointCollection
    south::Point
    north::Point
    nest2feeder::Float64
    azimuth::Float64
    originalnest::Point
end
function TransferNest(x) 
    y = Transfer(x)
    originalnest = point(x.data[:originalnest])
    TransferNest(y.feeder, y.track, y.pellet, y.south, y.north, y.nest2feeder, y.azimuth, originalnest)
end
Transfer(x::TransferNest) = Transfer(x.feeder, x.track, x.pellet, x.south, x.north, x.nest2feeder, x.azimuth)
struct TransferNestBelen <: DungMethod 
    feeder::Point
    track::Track
    pellet::PointCollection
    southbefore::Point
    northbefore::Point
    feederbefore::Point
    nestbefore::Point
    south::Point
    north::Point
end
function TransferNestBelen(x) 
    feeder, track, pellet = getdata(x.data)
    southbefore = point(x.data[:southbefore])
    northbefore = point(x.data[:northbefore])
    feederbefore = point(x.data[:feederbefore])
    nestbefore = point(x.data[:nestbefore])
    south = point(x.data[:south])
    north = point(x.data[:north])
    TransferNestBelen(feeder, track, pellet, rightdowninitial, leftdowninitial, rightupinitial, leftupinitial, rightdownfinal, leftdownfinal, rightupfinal, leftupfinal)
end
struct DawaySandpaper <: DungMethod
    feeder::Point
    nest::Point
    track::Track
    pellet::PointCollection
    rightdowninitial::Point
    leftdowninitial::Point
    rightupinitial::Point
    leftupinitial::Point
    rightdownfinal::Point
    leftdownfinal::Point
    rightupfinal::Point
    leftupfinal::Point
end
function DawaySandpaper(x) 
    feeder, track, pellet = getdata(x.data)
    nest = point(x.data[:nest])
    rightdowninitial = point(x.data[:rightdowninitial])
    leftdowninitial = point(x.data[:leftdowninitial])
    rightupinitial = point(x.data[:rightupinitial])
    leftupinitial = point(x.data[:leftupinitial])
    rightdownfinal = point(x.data[:rightdownfinal])
    leftdownfinal = point(x.data[:leftdownfinal])
    rightupfinal = point(x.data[:rightupfinal])
    leftupfinal = point(x.data[:leftupfinal])
    DawaySandpaper(feeder, nest, track, pellet, rightdowninitial, leftdowninitial, rightupinitial, leftupinitial, rightdownfinal, leftdownfinal, rightupfinal, leftupfinal)
end
struct Daway <: DungMethod
    feeder::Point
    nest::Point
    track::Track
    pellet::PointCollection
    initialfeeder::Point
end
function Daway(x) 
    feeder, track, pellet = getdata(x.data)
    nest = point(x.data[:nest])
    initialfeeder = point(x.data[:initialfeeder])
    Daway(feeder, nest, track, pellet, initialfeeder)
end

######################### DungMethod methods ###########

DungMethod(x, displace_direction::Missing, transfer::Missing, nest_coverage::Missing) = error("unidentified experimental setup")
DungMethod(x, displace_direction::Missing, transfer::Missing, nest_coverage) = ClosedNest(x)
function DungMethod(x, displace_direction::Missing, transfer, nest_coverage)
    if x.metadata.setup[:person] == "belen"
        TransferNestBelen(x)
    else
        if transfer == "back"
            TransferNest(x)
        else
            Transfer(x)
        end
    end
end
DungMethod(x, displace_direction, transfer::Missing, nest_coverage) = x.metadata.setup[:person] == "belen" ? DawaySandpaper(x) : Daway(x)

#=function DungMethod(displace_direction, person, transfer, nest_coverage)
if !ismissing(x.displace_direction)
if x.person == "belen"
DawaySandpaper(x)
else
Daway(x)
end
elseif !ismissing(x.transfer)
if x.person == "belen"
TransferNestBelen(x)
else
if x.transfer == "back"
TransferNest(x)
else
Transfer(x)
end
end
elseif x.nest_coverage == "closed"
ClosedNest(x)
else
error("unidentified experimental setup")
end
end=#

######################### Common methods ###########

mutable struct Common{N}
    feeder::Point
    nest::Point
    track::Track
    pellet::PointCollection
    originalnest::N
end
Common(x::ClosedNest) = Common(x.feeder, x.nest, x.track, x.pellet, x.nest)
nest(x::Common) = x.nest
turning(x::Common) = x.track.homing[end]
originalnest(x::Common) = x.originalnest

function Common(x::TransferNestBelen)
    v = x.northbefore - x.southbefore
    u = x.nestbefore - x.feederbefore 
    azimuth = atan(v[2], v[1]) - atan(u[2], u[1])
    nest2feeder = norm(x.nestbefore - x.feederbefore)
    v = x.north - x.south
    α = atan(v[2], v[1]) + azimuth
    u = Point(cos(α), sin(α))
    nest = x.feeder + u*nest2feeder
    Common(x.feeder, nest, x.track, x.pellet, missing)
end

function Common(x::Transfer)
    v = x.north - x.south
    α = atan(v[2], v[1]) + x.azimuth - π
    u = Point(cos(α), sin(α))
    nest = x.feeder + u*x.nest2feeder
    Common(x.feeder, nest, x.track, x.pellet, missing)
end

function Common(x::TransferNest)
    y = Common(Transfer(x))
    Common(y.feeder, y.nest, y.track, y.pellet, x.originalnest)
end

function Common(x::DawaySandpaper)
    originalnest = x.nest
    initial = mean(getproperty(x, k) for k in [:rightdowninitial, :leftdowninitial, :rightupinitial, :leftupinitial])
    final = mean(getproperty(x, k) for k in [:rightdownfinal, :leftdownfinal, :rightupfinal, :leftupfinal])
    v = final - initial
    nest = originalnest + v
    _feeder = x.feeder
    feeder = _feeder + v
    Common(feeder, nest, x.track, x.pellet, originalnest)
end

function Common(x::Daway)
    originalnest = x.nest
    v = x.feeder - x.initialfeeder
    nest = originalnest + v
    Common(x.feeder, nest, x.track, x.pellet, originalnest)
end

######################### END ######################

Common(x) = Common(DungMethod(x, get(x.metadata.setup, :displace_direction, missing), get(x.metadata.setup, :transfer, missing), get(x.metadata.setup, :nest_coverage, missing)))




#=x = rand(100)
i = 1:5
z = StructArray((x_cm = view(x, i), y_cm = view(x, 2 .+ i), t = view(x, 3 .+ i)))
z.t .-= z.t[1]=#


