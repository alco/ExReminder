#
# Test our event server.
#
# Copy and paste this code into running iex shell.
#

EventServer.start
EventServer.subscribe self
EventServer.add_event "Hey There!", "test", 1000
EventServer.listen 5
EventServer.cancel "Hey There!"
EventServer.add_event "Hey there2", "test", 5
EventServer.listen 10

# Test that it also accepts full datetime format
now_seconds = :calendar.datetime_to_gregorian_seconds :calendar.now_to_local_time(:erlang.now)
target_seconds = now_seconds + 5
target_datetime = :calendar.gregorian_seconds_to_datetime target_seconds
EventServer.add_event "Fulldate", "", target_datetime
EventServer.listen 6
