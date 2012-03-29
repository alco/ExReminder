#
# Test our event server.
#
# Copy and paste this code into running iex shell.
#

EventServer.start
EventServer.subscribe Process.self
EventServer.add_event "Hey There!", "test", 1000
EventServer.listen 5
EventServer.cancel "Hey There!"
EventServer.add_event "Hey there2", "test", 5
EventServer.listen 10
