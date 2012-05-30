sup_pid = EventSup.start EventServer, []

pid = Process.whereis EventServer

# Kill the server (simulating a crash). Is will be restarted by the supervisor
Process.exit pid, :die

# Kill it again
Process.exit Process.whereis(EventServer), :die

# Now will terminate the supervisor itself
Process.exit sup_pid, :shutdown

# Our event server is no longer there since it has been taken down by the
# supervisor
Process.whereis(EventServer) === :undefined
