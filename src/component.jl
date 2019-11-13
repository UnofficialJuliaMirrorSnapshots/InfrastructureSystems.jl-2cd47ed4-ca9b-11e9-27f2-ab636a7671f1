function add_forecast!(
                       component::T,
                       forecast::ForecastInternal,
                      ) where T <: InfrastructureSystemsType
    add_forecast!(_get_forecast_container(component), forecast)
    @debug "Added $forecast to $(typeof(component)) $(component.name) " *
           "num_forecasts=$(length(component._forecasts.data))."
end

"""
    remove_forecast_internal!(
                              ::Type{T},
                              component::InfrastructureSystemsType,
                              initial_time::Dates.DateTime,
                              label::AbstractString,
                             ) where T <: ForecastInternal

Removes the metadata for a forecast.
The caller must also remove the actual time series data.
"""
function remove_forecast_internal!(
                                   ::Type{T},
                                   component::InfrastructureSystemsType,
                                   initial_time::Dates.DateTime,
                                   label::AbstractString,
                                  ) where T <: ForecastInternal
    remove_forecast!(T, _get_forecast_container(component), initial_time, label)
    @debug "Removed forecast from $component:  $initial_time $label."
end

function clear_forecasts!(component::InfrastructureSystemsType)
    container = _get_forecast_container(component)
    if !isnothing(container)
        clear_forecasts!(container)
        @debug "Cleared forecasts in $component."
    end
end

"""
    get_forecast(
                 ::Type{T},
                 component::Component,
                 initial_time::Dates.DateTime,
                 label::AbstractString,
                ) where T <: Forecast

Return a forecast for the entire time series range stored for these parameters.
"""
function get_forecast(
                      ::Type{T},
                      component::InfrastructureSystemsType,
                      initial_time::Dates.DateTime,
                      label::AbstractString,
                     ) where T <: Forecast
    forecast_type = forecast_external_to_internal(T)
    forecast = get_forecast(forecast_type, component, initial_time, label)
    storage = _get_time_series_storage(component)
    ts = get_time_series(storage, get_time_series_uuid(forecast))
    return make_public_forecast(forecast, ts)
end

"""
    get_forecast(
                 ::Type{T},
                 component::InfrastructureSystemsType,
                 initial_time::Dates.DateTime,
                 label::AbstractString,
                 horizon::Int,
                ) where T <: Forecast

Return a forecast for a subset of the time series range stored for these parameters.
"""
function get_forecast(
                      ::Type{T},
                      component::InfrastructureSystemsType,
                      initial_time::Dates.DateTime,
                      label::AbstractString,
                      horizon::Int,
                     ) where T <: Forecast
    if !has_forecasts(component)
        throw(ArgumentError("no forecasts are stored in $component"))
    end

    first_forecast = iterate(iterate_forecasts(component))[1]
    resolution = get_resolution(first_forecast)
    sys_horizon = get_horizon(first_forecast)

    forecast = get_forecast(
        forecast_external_to_internal(T),
        component,
        initial_time,
        resolution,
        sys_horizon,
        label,
        horizon,
    )

    index = Int((initial_time - get_initial_time(forecast)) / resolution) + 1
    ts = get_time_series(
        _get_time_series_storage(component),
        get_time_series_uuid(forecast);
        index=index,
        len=horizon,
    )

    return make_public_forecast(forecast, ts)
end

function get_forecast(
                      ::Type{T},
                      component::InfrastructureSystemsType,
                      initial_time::Dates.DateTime,
                      label::AbstractString,
                     ) where T <: ForecastInternal
    return get_forecast(T, _get_forecast_container(component), initial_time, label)
end

function get_forecast(
                      ::Type{T},
                      component::InfrastructureSystemsType,
                      initial_time::Dates.DateTime,
                      sys_resolution::Dates.Period,
                      sys_horizon::Int,
                      label::AbstractString,
                      horizon::Int,
                     ) where T <: ForecastInternal
    end_time = initial_time + sys_resolution * horizon
    @debug "Requested forecast" initial_time horizon
    initial_times = get_forecast_initial_times(T, _get_forecast_container(component), label)
    for it in initial_times
        # Return the forecast for this time array if it encompasses the requested range and
        # one of its data points is the requested initial_time.
        if it <= initial_time && (end_time <= (it + sys_resolution * sys_horizon)) &&
                ((initial_time - it) % Dates.Millisecond(sys_resolution) == Dates.Second(0))
            return get_forecast(T, _get_forecast_container(component), it, label)
        end
    end

    throw(ArgumentError("did not find a forecast matching the requested parameters"))
end

"""
    get_forecast_values(
                        ::Type{T},
                        component::InfrastructureSystemsType,
                        initial_time::Dates.DateTime,
                        label::AbstractString,
                       ) where T <: Forecast

Return a TimeSeries.TimeArray where the forecast data has been multiplied by the forecasted
component field.
"""
function get_forecast_values(
                             ::Type{T},
                             mod::Module,
                             component::InfrastructureSystemsType,
                             initial_time::Dates.DateTime,
                             label::AbstractString,
                            ) where T <: Forecast
    forecast = get_forecast(T, component, initial_time, label)
    return get_forecast_values(mod, component, forecast)
end

function get_forecast_values(
                             mod::Module,
                             component::InfrastructureSystemsType,
                             forecast::Forecast)
    scaling_factors = get_data(forecast)
    label = get_label(forecast)
    accessor_func = getfield(mod, Symbol(label))
    data = scaling_factors .* accessor_func(component)
    return data
end

function has_forecasts(component::InfrastructureSystemsType)
    container = _get_forecast_container(component)
    return !isnothing(container) && !isempty(container)
end

function get_forecast_initial_times(
                                    ::Type{T},
                                    component::InfrastructureSystemsType,
                                   ) where T <: Forecast
    if !has_forecasts(component)
        throw(ArgumentError("$(typeof(component)) does not have forecasts"))
    end
    return get_forecast_initial_times(forecast_external_to_internal(T),
                                      _get_forecast_container(component))
end

function get_forecast_initial_times(
                                    ::Type{T},
                                    component::InfrastructureSystemsType,
                                    label::AbstractString,
                                   ) where T <: Forecast
    if !has_forecasts(component)
        throw(ArgumentError("$(typeof(component)) does not have forecasts"))
    end
    return get_forecast_initial_times(forecast_external_to_internal(T),
                                      _get_forecast_container(component),
                                      label)
end

function get_forecast_initial_times!(
                                     initial_times::Set{Dates.DateTime},
                                     component::InfrastructureSystemsType,
                                    )
    if !has_forecasts(component)
        throw(ArgumentError("$(typeof(component)) does not have forecasts"))
    end

    get_forecast_initial_times!(initial_times, _get_forecast_container(component))
end

function get_forecast_initial_times(component::InfrastructureSystemsType)
    if !has_forecasts(component)
        throw(ArgumentError("$(typeof(component)) does not have forecasts"))
    end

    initial_times = Set{Dates.DateTime}()
    get_forecast_initial_times!(initial_times, component)

    return sort!(collect(initial_times))
end

"""
    generate_initial_times(
                           component::InfrastructureSystemsType,
                           interval::Dates.Period,
                           horizon::Int;
                           initial_time::Union{Nothing, Dates.DateTime}=nothing,
                          )

Generates all possible initial times for the stored forecasts. This should return the same
result regardless of whether the forecasts have been stored as one contiguous array or
chunks of contiguous arrays, such as one 365-day forecast vs 365 one-day forecasts.

Throws ArgumentError if there are no forecasts stored, interval is not a multiple of the
system's forecast resolution, or if the stored forecasts have overlapping timestamps.

# Arguments
- `component::InfrastructureSystemsType`: Component containing forecasts.
- `interval::Dates.Period`: Amount of time in between each initial time.
- `horizon::Int`: Length of each forecast array.
- `initial_time::Union{Nothing, Dates.DateTime}=nothing`: Start with this time. If nothing,
  use the first initial time.
"""
function generate_initial_times(
                                component::InfrastructureSystemsType,
                                interval::Dates.Period,
                                horizon::Int;
                                initial_time::Union{Nothing, Dates.DateTime}=nothing,
                               )
    # This throws if no forecasts.
    existing_initial_times = get_forecast_initial_times(component)

    first_forecast = iterate(iterate_forecasts(component))[1]
    resolution = Dates.Second(get_resolution(first_forecast))
    sys_horizon = get_horizon(first_forecast)

    first_initial_time, total_horizon = check_contiguous_forecasts(
        component, existing_initial_times, resolution, sys_horizon,
    )

    if isnothing(initial_time)
        initial_time = first_initial_time
    end

    interval = Dates.Second(interval)

    if interval % resolution != Dates.Second(0)
        throw(ArgumentError(
            "interval=$interval is not a multiple of resolution=$resolution"
        ))
    end

    last_initial_time = first_initial_time + total_horizon * resolution -
                        horizon * resolution
    initial_times = Vector{Dates.DateTime}()
    for it in range(initial_time, step=interval, stop=last_initial_time)
        push!(initial_times, it)
    end

    return initial_times
end

"""
    are_forecasts_contiguous(component::InfrastructureSystemsType)
"""
function are_forecasts_contiguous(component::InfrastructureSystemsType)
    existing_initial_times = get_forecast_initial_times(component)
    first_initial_time = existing_initial_times[1]

    first_forecast = iterate(iterate_forecasts(component))[1]
    resolution = Dates.Second(get_resolution(first_forecast))
    horizon = get_horizon(first_forecast)
    total_horizon = horizon * length(existing_initial_times)

    return _are_forecasts_contiguous(existing_initial_times, resolution, horizon)
end

function _are_forecasts_contiguous(initial_times, resolution, horizon)
    if length(initial_times) == 1
        return true
    end

    for i in range(2, stop=length(initial_times))
        if initial_times[i] != initial_times[i - 1] + resolution * horizon
            return false
        end
    end

    return true
end

"""
Throws ArgumentError if the forecasts are not in consecutive order.
"""
function check_contiguous_forecasts(
                                    component::InfrastructureSystemsType,
                                    existing_initial_times,
                                    resolution::Dates.Period,
                                    horizon::Int
                                   )
    if !_are_forecasts_contiguous(existing_initial_times, resolution, horizon)
        throw(ArgumentError(
            "generate_initial_times is not allowed with overlapping timestamps"
        ))
    end

    first_initial_time = existing_initial_times[1]
    total_horizon = horizon * length(existing_initial_times)
    return first_initial_time, total_horizon
end

function get_forecast_keys(component::InfrastructureSystemsType)
    return keys(_get_forecast_container(component).data)
end

function get_forecast_labels(
                             ::Type{T},
                             component::InfrastructureSystemsType,
                             initial_time::Dates.DateTime,
                            ) where T <: Forecast
    return get_forecast_labels(forecast_external_to_internal(T),
                               _get_forecast_container(component),
                               initial_time)
end

function get_num_forecasts(component::InfrastructureSystemsType)
    container = _get_forecast_container(component)
    if isnothing(container)
        return 0
    end

    return length(container.data)
end

function get_time_series(component::InfrastructureSystemsType, forecast::Forecast)
    storage = _get_time_series_storage(component)
    return get_time_series(storage, get_time_series_uuid(forecast))
end

function get_time_series_uuids(component::InfrastructureSystemsType)
    container = _get_forecast_container(component)

    return [(get_time_series_uuid(container.data[key]), key.label)
             for key in get_forecast_keys(component)]
end

"""
This function must be called when a component is removed from a system.
"""
function prepare_for_removal!(component::InfrastructureSystemsType)
    # Forecasts can only be part of a component when that component is part of a system.
    clear_time_series!(component)
    set_time_series_storage!(component, nothing)
    clear_forecasts!(component)
    @debug "cleared all forecast data from" component
end

function iterate_forecasts(component::InfrastructureSystemsType)
    container = _get_forecast_container(component)
    forecast_keys = sort!(collect(keys(container.data)), by = x -> x.initial_time)

    Channel() do channel
        for key in forecast_keys
            put!(channel, container.data[key])
        end
    end
end

function clear_time_series!(component::InfrastructureSystemsType)
    storage = _get_time_series_storage(component)
    if !isnothing(storage)
        for (uuid, label) in get_time_series_uuids(component)
            remove_time_series!(storage, uuid, get_uuid(component), label)
        end
    end
end

function set_time_series_storage!(
                                  component::InfrastructureSystemsType,
                                  storage::Union{Nothing, TimeSeriesStorage},
                                 )
    container = _get_forecast_container(component)
    if !isnothing(container)
        set_time_series_storage!(container, storage)
    end
end

function validate_forecast_consistency(component::InfrastructureSystemsType)
    # Initial times for each label must be identical.
    initial_times = Dict{String, Vector{Dates.DateTime}}()
    for key in keys(_get_forecast_container(component).data)
        if !haskey(initial_times, key.label)
            initial_times[key.label] = Vector{Dates.DateTime}()
        end
        push!(initial_times[key.label], key.initial_time)
    end

    if isempty(initial_times)
        return true
    end

    base_its = nothing
    for (label, its) in initial_times
        sort!(its)
        if isnothing(base_its)
            base_its = its
        elseif its != base_its
            @error "initial times don't match" base_its, its
            return false
        end
    end

    return true
end

function _get_forecast_container(component::InfrastructureSystemsType)
    # TODO: The get__forecasts methods in PowerSystems need to be IS.get__forecasts.
    #container = get__forecasts(component)
    if :_forecasts in fieldnames(typeof(component))
        container = component._forecasts
    else
        container = nothing
    end

    return container
end

function _get_time_series_storage(component::InfrastructureSystemsType)
    container = _get_forecast_container(component)
    if isnothing(container)
        return nothing
    end

    return container.time_series_storage
end
