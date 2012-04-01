ExReminder
==========

This is a simple client-server application demonstrating the power of the
Erlang VM and the cuteness of [Elixir][2]. Based on this [chapter][3] from the
awesome ***Learn You Some Erlang for Great Good!*** book.

If you are have just read the [Getting Started][1] guide, you should first take
a look at this simple chat demo. It is probably the simplest client-server app
that can be written in Elixir. Try playing with it for a while until you feel
comfortable enough with writing you own modules and functions.

In this walkthrough I'm going to guide you through the code of a slightly more
advanced application which is also based on the client-server model. I'm
expecting that you are familiar with Erlang's core concepts such as processes
and message passing. If you're new to the Erlang/OTP ecosystem, don't be
discouraged. Try reading through the present tutorial. In case you find it
difficult to grasp at first, take a look at the following section where I give
a brief introduction into Erlang and point at a few helpful online resources
that will get you started quickly.

And if you are already familiar with Erlang and want to get more exposure to
Elixir, you may safely skip the following section and jump straight to _Getting
Practical_ further down the page.

## A Quick Intro to Erlang ##

...

## Laying Out The Design For Our Application ##

Now when you're all set to dive into building a real working application, refer
to the aforementioned [chapter][3] and read the first couple of sections. These
are explaining the application's design, messaging protocol and some details
about the final code structure. Once you reach the first code blocks, come back
here and we shall continue

## The Event Module ##

We'll start with the `Event` module. When a client asks the server to create an
event, the server spawns a new process from the `Event` module and then it
waits the specified amount of time before it calls back to the server which
then forwards the event's metadata back to the client.

Let's first get a birds-eye view at the code structure we're going to build.

```elixir
defmodule Event do
  defrecord Event.State, server: nil, name: "", to_go: 0

  ## Public API ##

  def start(event_name, delay)
  def start_link(event_name, delay)
  def init(server, event_name, delay)

  def cancel(pid)


  ## Private functions ##

  defp main_loop(state)
    server = state.server
    receive do
    match: {^server, ref, :cancel}
      # After sending :ok to the server, we leave this function basically
      # terminating the process. Thus, no reminder shall be sent.
      server <- { ref, :ok }

    after: state.to_go * 1000
      # The timeout has passed, now is the time to remind the server.
      server <- { :done, state.name }
    end
  end
end
```

This is basically the entire code for the module with some details omitted.

First, we define a record named `Event.State`. In it, we will store all the
state required for the event to run and contact the server when its time has
run out. Note we intentionally give the record a compound name to reflect its
relation to the `Event` module. Records in Elixir leave in a global namespace.
So, if we named this record simply `State` and then created another record for
the server module with the same name, we would get a name clash.

The first three functions are responsible for spawning a new `Event` process
and initializing the state with the data provided from outside. The difference
between `start` and `start_link` functions is that the former one will spawn an
independent process whereas the latter one will spawn a linked process, that
is, a process that will die if the server process dies. Because we'll have a
single server process, there is no need for all event processes stay around if
the server goes down. Creating each event process with the `start_link`
function allows us to achieve exactly that.

Next, we have a function for cancelling the event. This is done by sending a
`:cancel` message to the event process which is then received in the main loop.
If we look closely at the `main_loop` function, we'll that all it does is
hanging waiting for the `:cancel` message to arrive. Once it receives the
message, it simply returns `:ok` and exists the loop, thus terminating the
process.

However, if the timeout runs before `:cancel` is received, the event process
will send a reminder to the server, passing `:done` token along with its name.
It will then exit the main loop, as before, terminating the event process.

## Testing The Event Module ##

Notice how our `Event` module doesn't depend on the server module. All it does
is provide an interface for spawning new event processes and cancelling them.
It makes it easy to test the Event module separately to make sure eveything
works as expected.

Open the `test_event.exs` file and paste its contents to a running `iex`
instance. Make sure everything works as expected: the `iex` process
successfully receives a `{ :done, "Event" }` message from the first spawned
event process. Then we create another event will a bigger timeout value and
cancel it before the timeout has run out. Play around with it a little,
spawning multiple events and using the provided `flush` function to check that
you receive reminders from the events for which timeout has run out.

Once you're satisfied with the result, move on to the next section where we'll
implement the server.

## The EventServer Module ##

  [1]: http://elixir-lang.org/getting_started/1.html
  [2]: http://elixir-lang.org/
  [3]: http://learnyousomeerlang.com/designing-a-concurrent-application
