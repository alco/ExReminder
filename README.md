ExReminder
==========

This is a simple client-server application demonstrating the power of the
Erlang VM and the cuteness of [Elixir][2]. Based on this [chapter][3] from the
awesome ***Learn You Some Erlang for Great Good!*** book.

If you have just finished the [Getting Started][1] guide, you should first take
a look at [this chat demo][4]. It is probably the simplest client-server app that
can be written in Elixir. Try playing with it for a while until you feel
comfortable enough writing you own modules and functions.

In this walkthrough I'm going to guide you through the code of a slightly more
advanced application which is also based on the client-server model. I'm
expecting that you are familiar with Erlang's core concepts such as processes
and message passing. If you're new to the Erlang/OTP ecosystem, take a look at
the following section where you'll find pointers to a number of helpful online
resources.

If you are already familiar with Erlang and think you'r ready to get your hands
dirty with some Elixir code, you may safely skip the next section and jump
directly to _First Things First_.

## A Byte of Erlang ##

As Elixir's home page puts it,

> Elixir is a programming language built on top of the Erlang VM.

So, in order to write real application with Elixir, familiarity with Erlang's
concepts is required.

I have mentioned that the code for this tutorial is based on a chapter from the
great [Learn You Some Erlang for Great Good!][5] book. It is an excellent
introduction to Erlang, its design principles, standard library, best practices
and much more. Don't get discouraged, you don't need to read the whole book.
But you will at least need to get some familiarity with Erlang syntax anyway.
I've got a couple of useful pointer for you, those will get you up and running
in no time.

* This [Erlang Syntax: A Crash Course][6] provides a digest of the absolute
  minimum amount of knowledge you need to get to comfortably read Erlang code
  snippets and documentation. Each code snippet is accompanied by corresponding
  code in Elixir. This is an opportunity for you get some exposure to the
  Erlang's syntax and solidify what you've learned in the Getting Started
  guide.

* The [book][5] itself. Once you have read through the aforementioned crash
  course, you'll be able to safely skip the first couple of chapters in the
  book that deal with Erlang syntax mostly. Once you get to [The Hitchhiker's
  Guide to Concurrency][7] chapter, that's where the real fun starts and also
  the foundations the present tutorial is based on are layed out.

If you're looking at all this and start feeling discouraged, don't be! After
all, you can skip all this and dive straight into the code if you're confident
enough. Remember that when have any difficulties, don't hesitate to stop by the
`#elixir-lang` IRC channel on **irc.freenode.net** or send a message to the
[mailing list][9]. I can assure you there be some one willing to help you
traverse any obstacles you might stumble upon.

## First Things First ##

Before writing a single line of code, we have one prerequisite that needs to be done. , refer
to the aforementioned [chapter][3] and read the first couple of sections where
you'll find a detailed description (with pictures!) of the architecture and
messaging protocol for our application. As soon as you've got basic
understanding of the problem and the proposed design for solving it, come back
here and we shall start our walk through the code.

## The Event Module ##

We'll start with the `Event` module. When a client asks the server to create an
event, the server spawns a new process from the `Event` module and then it
waits the specified amount of time before it calls back to the server which
then forwards the event's metadata back to the client.

Let's first get a bird's-eye view at the code structure we're going to build.

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

This is basically the entire code for the module with a few details omitted.

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
  [4]: https://gist.github.com/2221616
  [5]: http://learnyousomeerlang.com/
  [6]: https://github.com/alco/elixir/wiki/Erlang-Syntax:-A-Crash-Course
  [7]: http://learnyousomeerlang.com/the-hitchhikers-guide-to-concurrency
  [8]: http://groups.google.com/group/elixir-lang-core
