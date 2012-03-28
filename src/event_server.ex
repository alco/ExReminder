defmodule EventServer do
    # We need to keep a list of all subscribe clients
    defrecord EventServer.State, events: nil, clients: nil

    # We also need to keep track of all event processes we spawn
    defrecord EventServer.Event, name: "", description: "", pid: nil, timeout: 0

    refer EventServer.State
    refer EventServer.Event

    # Main receive loop
    def msg_loop(state) do
        receive do
        match: { pid, msg_ref, {:subscribe, client} }
            # We'll be keeping a list of all subscribers and monitor them
            # so that we don't send useless messages to crashed clients
            ref = :erlang.monitor :process, client
            new_state = state.update_clients fn(clients) -> :orddict.store ref, client, clients end
            pid <- { msg_ref, :ok }
            msg_loop new_state

        match: { pid, msg_ref, {:add, name, description, timeout} }
            # TODO: validate the timeout value
            if timeout > 0 do
                event_pid = __MAIN__.Event.start_link name, timeout
                new_state = state.update_events fn(events) ->
                                :orddict.store name,
                                Event.new(name: name, description: description, pid: event_pid, timeout: timeout),
                                events
                            end
                pid <- { msg_ref, :ok }
                msg_loop new_state
            else:
                pid <- { msg_ref, {:error, :bad_timeout} }
                msg_loop state
            end

        match: { pid, msg_ref, {:cancel, name} }
            # If the event with the specified name is not found
            # we simply do nothing
            events = case :orddict.find name, state.events do
                        match: { :ok, event }
                            __MAIN__.Event.cancel event.pid
                            :orddict.erase name, state.events
                        match: :error
                            state.events
                     end
            pid <- { msg_ref, :ok }
            msg_loop state.events events

        match: { :done, name }
            #
            case :orddict.find name, state.events do
            match: { :ok, event }
                send_to_clients { :done, event.name, event.description }, state.clients
                msg_loop state.update_events fn(events) -> :orddict.erase name, events end
            match: :error
                # we cancel an event and it fires at the same time
                msg_loop state
            end

        match: :shutdown
            #
            exit :shutdown

        match: { 'DOWN', ref, :process, _pid, _reason }
            #
            msg_loop state.update_clients fn(clients) -> :orddict.erase ref, clients end

        match: :code_change
            #
            __MODULE__.msg_loop state

        match: else
            :io.format "Unknown message: ~p~n", [else]
            msg_loop state
        end
    end

    def init do
        msg_loop State.new events: :orddict.new, clients: :orddict.new
    end

    def start do
        :erlang.register __MODULE__, pid = :erlang.spawn __MODULE__, :init, []
        pid
    end

    def start_link do
        :erlang.register __MODULE__, pid = :erlang.spawn_link __MODULE__, :init, []
        pid
    end

    def terminate do
        __MODULE__ <- :shutdown
    end

    def subscribe(pid) do
        ref = :erlang.monitor :process, :erlang.whereis __MODULE__
        __MODULE__ <- { Process.self, ref, {:subscribe, pid} }
        receive do
        match: {ref, :ok }
            { :ok, ref }
        match: { 'DOWN', ref, :process, _pid, reason }
            { :error, reason }
        after: 5000
            { :error, :timeout }
        end
    end

    def add_event(name, description, timeout) do
        ref = :erlang.make_ref
        __MODULE__ <- { Process.self, ref, {:add, name, description, timeout} }
        receive do
        match: { ref, msg }
            msg
        after: 5000
            { :error, :timeout }
        end
    end

    def cancel(name) do
        ref = :erlang.make_ref
        __MODULE__ <- { Process.self, ref, {:cancel, name} }
        receive do
        match: { ref, :ok }
            :ok
        after: 5000
            { :error, :timeout }
        end
    end

    def listen(delay) do
        delay_msec = delay * 1000

        receive do
        match: m = { :done, _name, _description }
            [m | listen(0)]
        after: ^delay_msec
            []
        end
    end

    defp send_to_clients(msg, clients) do
        :orddict.map fn(_ref, pid) ->
            pid <- msg
        end, clients
    end
end
