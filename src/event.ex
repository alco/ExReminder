defmodule Event do
    defrecord Event.State, server: nil, name: "", to_go: 0

    refer Event.State

    def msg_loop(state) do
        server = state.server
        timeout = state.to_go * 1000
        receive do
        match: {^server, ref, :cancel}
            server <- { ref, :ok }
        after: ^timeout
            server <- { :done, state.name }
        end
    end

    def start(event_name, delay) do
        :erlang.spawn __MODULE__, :init, [Process.self, event_name, delay]
    end

    def start_link(event_name, delay) do
        :erlang.spawn_link __MODULE__, :init, [Process.self, event_name, delay]
    end

    def init(server, event_name, delay) do
        msg_loop State.new server: server, name: event_name, to_go: delay
    end

    def cancel(pid) do
        # Monitor in case the process is already dead
        ref = :erlang.monitor :process, pid
        pid <- { Process.self, ref, :cancel }
        receive do
        match: { ^ref, :ok }
            :erlang.demonitor ref, [:flush]
            :ok
        match: { DOWN, ^ref, :process, ^pid, _reason }
            :ok
        end
    end
end
