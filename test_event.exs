#
# Exercise the public API of the Event module.
#
# First, compile the event.ex file. Then run iex and paste the code from this
# file into it.
#

# A helper function
# Flushes all currently available messages to standard output.
flush = fn() ->
    f = fn(f) ->
        receive do
        match: x
            s = inspect x
            IO.puts "Shell got #{s}"
            f.(f)
        after: 0
            :ok
        end
    end
    f.(f)
end

# Spawn a new Event process
Event.start "Event", 0

# Print out all pending messages
flush.()

# This time we keep a reference to the new process around so that we can
# cancel it later
pid = Event.start "Another event", 500
Event.cancel pid
