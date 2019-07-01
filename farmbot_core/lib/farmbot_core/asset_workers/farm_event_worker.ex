defimpl FarmbotCore.AssetWorker, for: FarmbotCore.Asset.FarmEvent do
  use GenServer
  require Logger

  alias FarmbotCore.{
    Asset,
    Asset.FarmEvent,
    Asset.Regimen,
    Asset.Sequence
  }

  alias FarmbotCeleryScript.{Scheduler, AST, Compiler}
  defstruct [:farm_event, :datetime, :handle_sequence, :handle_regimen]
  alias __MODULE__, as: State

  @checkup_time_ms Application.get_env(:farmbot_core, __MODULE__)[:checkup_time_ms]
  @checkup_time_ms ||
    Mix.raise("""
    config :farmbot_core, #{__MODULE__}, checkup_time_ms: 10_000
    """)

  def preload(%FarmEvent{}), do: []

  def tracks_changes?(%FarmEvent{}), do: false

  def start_link(farm_event, args) do
    GenServer.start_link(__MODULE__, [farm_event, args])
  end

  def init([farm_event, args]) do
    # Logger.disable(self())
    Logger.warn("FarmEvent: #{inspect(farm_event)} is initializing")
    ensure_executable!(farm_event)
    now = DateTime.utc_now()
    handle_sequence = Keyword.get(args, :handle_sequence, &handle_sequence/2)
    handle_regimen = Keyword.get(args, :handle_regimen, &handle_regimen/3)

    unless is_function(handle_sequence, 2) do
      raise "FarmEvent Sequence handler should be a 2 arity function"
    end

    unless is_function(handle_regimen, 3) do
      raise "FarmEvent Regimen handler should be a 3 arity function"
    end

    state = %State{
      farm_event: farm_event,
      handle_regimen: handle_regimen,
      handle_sequence: handle_sequence,
      datetime: farm_event.last_executed || DateTime.utc_now()
    }

    # check if now is _before_ start_time
    case DateTime.compare(now, farm_event.start_time) do
      :lt ->
        init_event_started(state, now)

      _ ->
        # check if now is _after_ end_time
        case DateTime.compare(now, farm_event.end_time) do
          :gt -> init_event_completed(state, now)
          _ -> init_event_started(state, now)
        end
    end
  end

  defp init_event_completed(%{farm_event: %{executable_type: "Regimen"}} = state, _) do
    {:ok, state, 0}
  end

  defp init_event_completed(_, _) do
    Logger.warn("No future events")
    :ignore
  end

  def init_event_started(%State{} = state, _now) do
    {:ok, state, 0}
  end

  def handle_info(:timeout, %State{} = state) do
    next = FarmEvent.build_calendar(state.farm_event, state.datetime)

    if next do
      # positive if the first date/time comes after the second.
      diff = DateTime.compare(next, DateTime.utc_now())
      # if next_event is more than 0 milliseconds away, schedule that event.
      case diff do
        :gt ->
          Logger.info("Event is still in the future")
          {:noreply, state, @checkup_time_ms}

        diff when diff in [:lt, :eq] ->
          Logger.info("Event should be executed:  #{Timex.from_now(next)}")
          executable = ensure_executable!(state.farm_event)

          event =
            ensure_executed!(
              state.farm_event,
              executable,
              next,
              state.handle_sequence,
              state.handle_regimen
            )

          {:noreply, %{state | farm_event: event, datetime: DateTime.utc_now()}, @checkup_time_ms}
      end
    else
      Logger.warn("No more future events to execute.")
      {:stop, :normal, state}
    end
  end

  def handle_info({Scheduler, _, _}, state) do
    {:noreply, state, @checkup_time_ms}
  end

  defp ensure_executed!(
         %FarmEvent{last_executed: nil} = event,
         %Sequence{} = exe,
         next_dt,
         handle_sequence,
         _
       ) do
    # positive if the first date/time comes after the second.
    comp = Timex.diff(DateTime.utc_now(), next_dt, :minutes)

    cond do
      # now is more than 2 minutes past expected execution time
      comp > 2 ->
        Logger.warn("Sequence: #{inspect(exe)} too late: #{comp} minutes difference.")
        event

      true ->
        Logger.warn("Sequence: #{inspect(exe)} has not run before: #{comp} minutes difference.")
        apply(handle_sequence, [exe, event.body])
        update_last_executed(event, next_dt)
    end
  end

  defp ensure_executed!(%FarmEvent{} = event, %Sequence{} = exe, next_dt, handle_sequence, _) do
    # positive if the first date/time comes after the second.
    comp = Timex.diff(event.last_executed, next_dt, :seconds)
    cond do
      # last_execution is more than 2 minutes past expected execution time
      comp < -2000 ->
        Logger.warn("Sequence: #{exe.id} too late: #{comp} seconds difference.")
        update_last_executed(event, next_dt)
      # comp > 0 and comp < 2 ->
      #   Logger.warn("Sequence: #{exe.id} needs executing")
      #   apply(handle_sequence, [exe, event.body])
      #   update_last_executed(event, next_dt)
      comp < 0 ->
        Logger.warn("Sequence: #{exe.id} needs executing #{comp} seconds difference.")
        apply(handle_sequence, [exe, event.body])
        update_last_executed(event, next_dt)
      true ->
        Logger.warn("""
        what do?:
        last_executed=#{inspect(event.last_executed)}
        next_dt=#{inspect(next_dt)}
        comp=#{comp}
        """)
        event
    end
  end

  defp ensure_executed!(
         %FarmEvent{last_executed: nil} = event,
         %Regimen{} = exe,
         next_dt,
         _,
         handle_regimen
       ) do
    Logger.warn("Regimen: #{inspect(exe)} has not run before. Executing it.")
    apply(handle_regimen, [exe, event, %{started_at: next_dt}])
    Asset.update_farm_event!(event, %{last_executed: next_dt})
  end

  defp ensure_executed!(%FarmEvent{} = event, %Regimen{} = exe, _next_dt, _, handle_regimen) do
    apply(handle_regimen, [exe, event, %{}])
    event
  end

  defp ensure_executable!(%FarmEvent{executable_type: "Sequence", executable_id: id}) do
    Asset.get_sequence(id) || raise("Sequence #{id} is not synced")
  end

  defp ensure_executable!(%FarmEvent{executable_type: "Regimen", executable_id: id}) do
    Asset.get_regimen(id) || raise("Regimen #{id} is not synced")
  end

  @doc false
  def handle_regimen(regimen, event, params) do
    Asset.upsert_regimen_instance!(regimen, event, params)
  end

  defp handle_sequence(sequence, farm_event_body) do
    param_appls = AST.decode(farm_event_body)
    celery_ast =  AST.decode(sequence)

    celery_ast = %{
      celery_ast
      | args: %{
          celery_ast.args
          | locals: %{celery_ast.args.locals | body: celery_ast.args.locals.body ++ param_appls}
        }
    }

    compiled_celery = Compiler.compile(celery_ast)
    Scheduler.schedule(compiled_celery)
  end

  defp update_last_executed(event, next_dt) do
    # TODO(Connor) This causes the event to be restarted.
    # Similarly to RegimenInstance worker.
    Asset.update_farm_event!(event, %{last_executed: next_dt})
    # %{event | last_executed: next_dt}
  end

end
