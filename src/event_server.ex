#
# This is our singleton event server. It implements messaging with clients as
# well as Event processes. Details of the messaging protocol are hidden behind
# a simple API.
#
defmodule EventServer do
    # We need to keep a list of all pending events and subscribed clients
    defrecord EventServer.State, events: [], clients: []
    refer EventServer.State

    # Event description
    defrecord EventServer.Event, name: "", description: "", pid: nil, timeout: 0
    refer EventServer.Event


    ## Public API ##

    def start do
        # Register the server process so that it can be referred to as
        # EventServer by clients
        Process.register __MODULE__, pid = :erlang.spawn __MODULE__, :init, []
        pid
    end

    def start_link do
        Process.register __MODULE__, pid = :erlang.spawn_link __MODULE__, :init, []
        pid
    end

    def init do
        main_loop State.new
    end

    # Create a new event with a unique name
    def add_event(name, description, timeout) do
        ref = make_ref
        __MODULE__ <- { Process.self, ref, {:add, name, description, timeout} }
        receive do
        match: { ^ref, msg }
            msg
        after: 5000
            { :error, :timeout }
        end
    end

    # Subscribe to event notifications
    def subscribe(pid) do
        # Here we can use `whereis` to find out the pid because we have
        # registered our module in the `start` (and `start_link`) function
        mon = Process.monitor :erlang.whereis __MODULE__
        __MODULE__ <- { Process.self, mon, {:subscribe, pid} }
        receive do
        match: { ^mon, :ok }
            { :ok, mon }
        match: { 'DOWN', ^mon, :process, ^pid, reason }
            { :error, reason }
        after: 5000
            { :error, :timeout }
        end
    end

    # Cancel the event with name 'name'
    def cancel(name) do
        ref = :erlang.make_ref
        __MODULE__ <- { Process.self, ref, {:cancel, name} }
        receive do
        match: { ^ref, :ok }
            :ok
        after: 5000
            { :error, :timeout }
        end
    end

    # Shut down the server
    def terminate do
        __MODULE__ <- :shutdown
    end

    # Wait until all events have fired or the timeout has passed
    def listen(delay) do
        receive do
        match: m = { :done, _name, _description }
            [m | listen(0)]
        after: delay * 1000
            []
        end
    end


    ## Private functions ##

    # The main receive loop
    defp main_loop(state) do
        receive do
        match: { pid, msg_ref, {:subscribe, client} }
            # We'll keep a list of all subscribers and monitor them
            # so that we don't send useless messages to crashed clients
            mon = :erlang.monitor :process, client
            new_state = state.update_clients fn(clients) -> Orddict.put(clients, mon, client) end
            pid <- { msg_ref, :ok }
            main_loop new_state

        match: { pid, msg_ref, {:add, name, description, timeout} }
            if timeout > 0 do
                # Use the fully qualified name __MAIN__.Event to refer to the
                # Event module and not our referred EventServer.Event record
                event_pid = __MAIN__.Event.start_link name, timeout
                new_state = state.update_events fn(events) ->
                                Orddict.put(
                                    events,
                                    name,
                                    Event.new(name: name, description: description, pid: event_pid, timeout: timeout)
                                )
                            end
                pid <- { msg_ref, :ok }
                main_loop new_state
            else:
                pid <- { msg_ref, {:error, :bad_timeout} }
                main_loop state
            end

        match: { pid, msg_ref, {:cancel, name} }
            # If the event with the specified name is not found,
            # we simply do nothing
            events = case :orddict.find(name, state.events) do
                     match: { :ok, event }
                         __MAIN__.Event.cancel event.pid
                         :orddict.erase(name, state.events)
                     match: :error
                         state.events
                     end
            pid <- { msg_ref, :ok }
            main_loop state.events events

        match: { :done, name }
            # The event has finished, notify all clients
            case :orddict.find(name, state.events) do
            match: { :ok, event }
                send_to_clients { :done, event.name, event.description }, state.clients
                main_loop state.update_events fn(events) -> :orddict.erase(name, events) end
            match: :error
                # This happens if we cancel an event and it fires at the same time
                main_loop state
            end

        match: :shutdown
            # Since we create each new event by calling `start_link`, all event
            # processes will also be terminated.
            exit :shutdown

        match: { 'DOWN', ref, :process, _pid, _reason }
            # A client has crashed
            main_loop state.update_clients fn(clients) -> :orddict.erase(ref, clients) end

        match: :code_change
            # New code has arrived! Time to upgrade.
            # The upgrade process is performed by using the qualified name
            # __MODULE__.main_loop. Calling 'main_loop' instead would continue
            # running the old code.
            __MODULE__.main_loop state

        match: else
            # Someone sent us a message we don't understand
            :io.format "Unknown message: ~p~n", [else]
            main_loop state
        end
    end


    # Send 'msg' to each subscribed client
    def send_to_clients(msg, clients) do
        Enum.map clients, fn({_ref, pid}) ->
            pid <- msg
        end
    end
end
