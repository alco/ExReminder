#
# Every event in our reminder app is a separate Event process.
# It basically sits inside the 'receive' block waiting for :cancel message.
# When the timeout has passed and no :cancel message has been received,
# it sends the :done message to the server.
#
# While this module depends on a server, it does not known anything about it.
# Therefore, we can easily test it from the shell or by implementing a minimal
# server to exercise its API.
#
defmodule Event do
  defrecord Event.State, server: nil, name: "", to_go: 0

  # This sets up an alias for the record so that we can simply use State to
  # refer to it inside the module
  refer Event.State


  ## Public API ##

  def start(event_name, delay) do
    :erlang.spawn __MODULE__, :init, [Process.self, event_name, delay]
  end

  def start_link(event_name, delay) do
    :erlang.spawn_link __MODULE__, :init, [Process.self, event_name, delay]
  end

  def init(server, event_name, delay) do
    main_loop State.new server: server, name: event_name, to_go: delay
  end

  def cancel(pid) do
    # Create a monitor to know when the process dies
    mon = Process.monitor pid
    pid <- { Process.self, mon, :cancel }
    receive do
    match: { ^mon, :ok }
      Process.demonitor mon, [:flush]
      :ok
    match: { DOWN, ^mon, :process, ^pid, _reason }
      # The server is down. We're ok with that.
      :ok
    end
  end


  ## Private functions ##

  # This is not actually a loop, but it is all the same the main
  # function in which our process spends most of the time
  defp main_loop(state) do
    server = state.server
    receive do
    match: {^server, ref, :cancel}
      # After sending :ok to the server, we leave this function, basically
      # terminating the process. Thus, no reminder shall be sent.
      server <- { ref, :ok }

    after: state.to_go * 1000
      # The timeout has passed, now is the time to remind the server.
      server <- { :done, state.name }
    end
  end
end
