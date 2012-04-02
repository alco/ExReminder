ExReminder
==========

This is a simple client-server application demonstrating the power of the
Erlang VM and the cuteness of [Elixir][2]. Based on this [chapter][3] from the
awesome [Learn You Some Erlang for Great Good!][5] book.

If you have just finished the [Getting Started][1] guide, you should first take
a look at [this chat demo][4]. It is probably the simplest client-server app that
can be written in Elixir. Try playing with it for a while until you feel
comfortable enough writing you own modules and functions.

In this walkthrough I'm going to guide you through the code of a slightly more
advanced application which also implements a client-server model. I'm expecting
that you are familiar with Erlang's core concepts such as processes and message
passing. If you're new to the Erlang/OTP ecosystem, take a look at the
following section where you'll find pointers to a number of helpful online
resources.

If you are already familiar with Erlang and feel confident enough to get your
hands dirty with some Elixir code, you may safely skip the next section and
jump directly to _First Things First_. (Although you might still find the crash
course on Erlang syntax useful, as it compares Erlang snippets with
corresponding Elixir code.)

* auto-gen TOC:
{:toc}

## A Byte of Erlang ##

As Elixir's home page puts it,

> Elixir is a programming language built on top of the Erlang VM.

So, in order to write a real application with Elixir, familiarity with Erlang's
concepts is required. Here's a few links to online resources that cover Erlang's fundamentals:

* This [Erlang Syntax: A Crash Course][6] (authored by yours truly) provides a
  concise intro to Erlang's syntax. Each code snippet is accompanied by
  equivalent code in Elixir. This is an opportunity for you to not only get
  some exposure to the Erlang's syntax but also review some of the things you
  have learned in the [Getting Started][1] guide.

* Erlang's official website has a short [tutorial][9] with pictures that
  briefly describe Erlang's primitives for concurrent programming.

* A larger and more comprehensive [guide][10] from Erlang's official
  documentation site.

* I have mentioned that the code for this tutorial is based on a chapter from
  the great [Learn You Some Erlang for Great Good!][5] book. It is an excellent
  introduction to Erlang, its design principles, standard library, best
  practices and much more. If you are serious about Elixir, you'll want to get
  a solid understanding of Erlang's fundamentals. Once you have read through
  the crash course mentioned above, you'll be able to safely skip the first
  couple of chapters in the book that mostly deal with Erlang syntax. When you
  get to [The Hitchhiker's Guide to Concurrency][7] chapter, that's where the
  real fun starts. It is also a good starting point for this tutorial since
  this chapter and the ones that follow it explain many of the concepts we'll
  see in ExReminder's source code.

If you're looking at all this and start feeling discouraged, please don't!
After all, you can the theory and dive straight into the code. You are free to
take any approach you wish as long as you're enjoying the process. Remember
that in case of any difficulties, you can always visit the **#elixir-lang**
channel on **irc.freenode.net** or send a message to the [mailing list][8]. I
can assure you, there will be someone willing to help.

## First Things First ##

Before writing a single line of code, we need think a little about the problem
we're facing and the goals we're trying to achieve. Refer to the aforementioned
[chapter][3] and read the first couple of sections where you'll find a detailed
description (with pictures!) of the architecture and messaging protocol for our
application. As soon as you've got a basic understanding of the problem and the
proposed design for solving it, come back here and we shall start our walk
through the code.

## The Event Module ##

We'll start with the `Event` module. In our application, when a client asks the
server to create an event, the server spawns a new Event process which then
waits for the specified amount of time before it calls back to the server which
then forwards the event's name back to the client.

```elixir
defmodule Event do
  defrecord Event.State, server: nil, name: "", to_go: 0

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
```

First, we define a record named `Event.State`. In it we will store all the
state required for the event to run and contact the server when its time has
run out. Note that we intentionally give the record a compound name to reflect
its relation to the `Event` module. Records in Elixir leave in a global
namespace.  So, if we named this record simply `State` and then created another
record for the server module with the same name, we would get a name clash.

The first three functions are responsible for spawning a new Event process and
initializing the state with the data provided from outside. Here we call
Erlang's `spawn` and `spawn_link` functions directly. Elixir may provide
wrappers for those at some point in the future. `__MODULE__` is one of Elixir's
read-only pseudo-variables. Similarly to Erlang's `?MODULE`, it expands to the
current module's name at compile time. The other pseudo-variables in Elixir
are

* `__FUNCTION__` — returns a tuple representing the current function by name and arity or nil;
* `__LINE__` — returns an integer representing the current line;
* `__FILE__` — returns a string representing the current file;
* `__MAIN__` — the main namespace where modules are stored. For instance, `List` can also be accessed as `__MAIN__.List`;
* `__LOCAL__` — works as a proxy to force a function call to resolve locally (and not be expanded as a macro).

In the `init` function we create a new `State` record passing initial values as
an orddict. If you prefer more formal syntax, you could rewrite it in one of
the following ways:

```elixir
State.new [server: server, name: event_name, to_go: delay]
# or
State.new([server: server, name: event_name, to_go: delay])

# Note, however, that you cannot pass a list of tuples, because `new` expects
an orddict (which is an _ordered_ list of tuples)
```

When it doesn't introduce ambiguity, it is recommended to use the first approach.

---

Next, we have a function for cancelling an event.

```elixir
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
```

This is done by sending a `:cancel` message to the event process which is then
received in the main loop.  If we look closely at the `main_loop` function
below, we'll see that all it does is hang waiting for the `:cancel` message to
arrive.  Once it receives the message, it simply returns `:ok` and exists the
loop, thus terminating the process.

We use a left-arrow operator `<-` to send a message (Erlang uses `!` for the
same purpose). Also note the use of the caret `^` symbol. When you do pattern
matching in Elixir and you want to match against the value of a variable
(rather than bind the variable to a new value), prepend the variable's name
with a caret.

---

The last function in our `Event` module is the main loop of the process.

```elixir
  defp main_loop(state) do
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
```

It is not actually a loop, strictly speaking, but you get the point. Every
Event process spends most of its lifetime in this function. Other than the fact
that we use `defp` instead of `def` to keep this function private to the `Event`
module, there is nothing new in this particular piece of code.

## Testing The Event Module ##

Notice how our `Event` module doesn't depend on the server module or any other
module for that matter. All it does is provide an interface for spawning new
event processes and cancelling them. This approach makes it easy to test the
`Event` module in isolation and make sure eveything works as expected.

Launch `iex` inside the project's directory, then open the `test_event.exs`
file and paste its contents into the running Elixir shell. Make sure everything
is working as expected: the `iex` process successfully receives a `{ :done,
"Event" }` message from the first spawned event process. Then we create another
event with a larger timeout value and cancel it before the timeout runs out.
Play around with it for a while, spawning multiple events and using the provided
`flush` function to check that you receive reminders from the spawned events.

Once you're satisfied with the result, move on to the next section where we're
going to take a closer look at the event server.

## The EventServer Module ##

  [1]: http://elixir-lang.org/getting_started/1.html
  [2]: http://elixir-lang.org/
  [3]: http://learnyousomeerlang.com/designing-a-concurrent-application
  [4]: https://gist.github.com/2221616
  [5]: http://learnyousomeerlang.com/
  [6]: https://github.com/alco/elixir/wiki/Erlang-Syntax:-A-Crash-Course
  [7]: http://learnyousomeerlang.com/the-hitchhikers-guide-to-concurrency
  [8]: http://groups.google.com/group/elixir-lang-core
  [9]: http://www.erlang.org/course/concurrent_programming.html
  [10]: http://www.erlang.org/doc/getting_started/users_guide.html
