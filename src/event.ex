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
  defrecord State, server: nil, name: "", to_go: 0


  ## Public API ##

  def start(event_name, delay) do
    spawn __MODULE__, :init, [Process.self, event_name, delay]
  end

  def start_link(event_name, delay) do
    spawn_link __MODULE__, :init, [Process.self, event_name, delay]
  end

  def init(server, event_name, delay) do
    main_loop State.new server: server, name: event_name, to_go: datetime_to_seconds(delay)
  end

  def cancel(pid) do
    # Create a monitor to know when the process dies
    mon = Process.monitor pid
    pid <- { Process.self, mon, :cancel }
    # Note the use of the caret ^ to match against variable value
    receive do
    match: { ^mon, :ok }
      # The event has been cancelled successfully
      Process.demonitor mon, [:flush]
      :ok
    match: { :DOWN, ^mon, :process, ^pid, _reason }
      # The event process is already down. We're ok with that.
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

  # When supplied with a date-time in a specified format,
  # convert it to the number of seconds from now up to that date.
  #
  # If the date is in the past, return 0.
  #
  # Note that the timeout value used by the event process has a hard limit
  # forced by the Erlang runtime. It is around 50 days by default.
  defp datetime_to_seconds({{_year, _month, _day}, {_hour, _minute, _second}} = datetime) do
    now = :calendar.local_time
    to_go = :calendar.datetime_to_gregorian_seconds(datetime) \
            - :calendar.datetime_to_gregorian_seconds(now)
    timeout = if to_go > 0, do: to_go, else: 0
    timeout
  end

  # Still support the timeout in seconds
  defp datetime_to_seconds(seconds) when is_number(seconds) do
    if seconds > 0, do: seconds, else: 0
  end
end
