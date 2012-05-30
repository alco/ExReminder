#
# This is our singleton event server. It implements messaging with clients as
# well as Event processes. Details of the messaging protocol are hidden behind
# a simple API.
#
defmodule EventServer do
  # We need to keep a list of all pending events and subscribed clients
  defrecord State, events: [], clients: []

  # Event description
  defrecord Event, name: "", description: "", pid: nil, timeout: 0


  ## Public API ##

  def start do
    # Register the server process so that it can be referred to as
    # EventServer by clients
    Process.register __MODULE__, pid = spawn __MODULE__, :init, []
    pid
  end

  def start_link do
    Process.register __MODULE__, pid = spawn_link __MODULE__, :init, []
    pid
  end

  def init(state // nil) do
    # Here, instead of creating a new state, we could load events from a file
    # if we saved them previously. Events can be stored into a file each time
    # an event is added, cancelled, or finished; in other words, each time the
    # `events` list of our State record is updated.
    state =
      if state === nil do
        State.new
      else
        state
      end
    main_loop state
  end

  # Create a new event with a unique name
  def add_event(name, description, timeout) do
    ref = make_ref
    __MODULE__ <- { Process.self, ref, {:add, name, description, timeout} }
    receive do
      { ^ref, msg } ->
        msg
      after 5000 ->
        { :error, :timeout }
    end
  end

  # Subscribe to event notifications
  def subscribe(pid) do
    # Here we can use `whereis` to find out the pid because we have
    # registered our module in the `start` (and `start_link`) function
    mon = Process.monitor Process.whereis __MODULE__
    __MODULE__ <- { Process.self, mon, {:subscribe, pid} }
    receive do
      { ^mon, :ok } ->
        { :ok, mon }
      { :DOWN, ^mon, :process, ^pid, reason } ->
        { :error, reason }
      after 5000 ->
        { :error, :timeout }
    end
  end

  # Cancel the event with name 'name'
  def cancel(name) do
    ref = make_ref
    __MODULE__ <- { Process.self, ref, {:cancel, name} }
    receive do
      { ^ref, :ok } ->
        :ok
      after 5000 ->
        { :error, :timeout }
    end
  end

  # Shut down the server
  def terminate do
    __MODULE__ <- :shutdown
  end

  # Wait until at least one event has fired or the timeout has passed
  def listen(delay) do
    receive do
      # We prepend underscores to variable names to silence the compiler (at
      # tends to complain about unused variables)
      m = { :done, _name, _description } ->
        [m | listen(0)]
      after delay * 1000 ->
        []
    end
  end


  ## Private functions ##

  # The main receive loop
  defp main_loop(state) do
    receive do
    { pid, msg_ref, {:subscribe, client} } ->
      # We'll keep a list of all subscribers and monitor them
      # so that we don't send useless messages to crashed clients
      mon = Process.monitor client

      # The `update_clients` function was generated by Elixir when we defined
      # the State record. It receives a one-argument function passing it the
      # current value of the `clients` field and sets the value of the
      # field to the return value of the function.
      new_state = state.update_clients fn(clients) -> :orddict.store(mon, client, clients) end
      pid <- { msg_ref, :ok }
      main_loop new_state

    { pid, msg_ref, {:add, name, description, timeout} } ->
      # Use the fully qualified name __MAIN__.Event to refer to the
      # Event module and not our referred EventServer.Event record
      event_pid = __MAIN__.Event.start_link name, timeout
      new_state = state.update_events fn(events) ->
                    :orddict.store(
                      name,
                      Event.new(name: name, description: description, pid: event_pid, timeout: timeout),
                      events
                    )
                  end
      pid <- { msg_ref, :ok }
      main_loop new_state

    { pid, msg_ref, {:cancel, name} } ->
      # If an event with the specified name is not found, we simply do nothing.
      # If it is found, we send it a :cancel message and remove from our list
      # of events.
      events = case :orddict.find(name, state.events) do
                 :error ->
                   state.events
                 { :ok, event } ->
                   __MAIN__.Event.cancel event.pid
                   :orddict.erase name, state.events
               end
      pid <- { msg_ref, :ok }
      # This call will update the values of the `events` field
      new_state = state.events events
      main_loop new_state

    { :done, name } ->
      # The event has finished, notify all clients
      case :orddict.find(name, state.events) do
        :error ->
          # This happens if we cancel an event and it fires at the same time
          main_loop state
        { :ok, event } ->
          send_to_clients { :done, event.name, event.description }, state.clients
          main_loop state.update_events fn(events) -> :orddict.erase(name, events) end
      end

    :shutdown ->
      # Since we create each new event by calling `start_link`, all event
      # processes will also be terminated.
      exit :shutdown

    { :DOWN, ref, :process, _pid, _reason } ->
      # A client has crashed. Remove it from our subscribers list.
      main_loop state.update_clients fn(clients) -> :orddict.erase(ref, clients) end

    :code_change ->
      # New code has arrived! Time to upgrade.
      #
      # The upgrade process is performed by using the qualified name
      # __MODULE__.init. Calling 'main_loop' instead would continue running the
      # old code. We can't to a call __MODULE__.main_loop, because 'main_loop'
      # is a private function. For this reason, we're doing a recursive call
      # through the 'init' function.
      __MODULE__.init state

    other ->
      # Someone sent us a message we don't understand
      IO.puts "Unknown message: #{inspect other}"
      main_loop state
    end
  end

  # Send 'msg' to each subscribed client
  defp send_to_clients(msg, clients) do
    Enum.map clients, fn({_ref, pid}) ->
      pid <- msg
    end
  end
end
