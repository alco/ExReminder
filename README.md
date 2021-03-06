ExReminder
==========

***Important notice*** _Elixir is still being actively developed, so the code
in this tutorial might break. If it doesn't work for you, please file an issue
or send a note to the [mailing list][8]. Thanks for understanding :)_

This is a simple client-server application demonstrating the power of the
Erlang VM and the cuteness of [Elixir][2]. Based on this [chapter][3] from the
awesome [Learn You Some Erlang for Great Good!][5] book.

If you have just finished the [Getting Started guide][1], you should first take
a look at [this chat demo][4]. It is probably the simplest client-server app that
can be written in Elixir. Try playing with it for a while until you feel
comfortable enough writing you own modules and functions.

In this tutorial I'm going to guide you through the code of a slightly more
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

## Running examples ##

A couple of examples are provided to demonstrate the usage of the API we're
going to build. The best way to run them is to start `iex` and paste the code
into it. If you try to run them like so

```
elixir test_event.exs
```

you might get unexpected results.

## Erlang ##

Be sure to look at the section called _A Byte of Erlang_ in this [chapter][15]
of the Getting Started guide if you haven't got a chance to play with Erlang
before. The present tutorial assumes you have familiarity with Erlang's basic
concepts like processes, receive loops, message passing, etc. Knowledge of OTP
is not required, though.

If you're looking at this and start feeling discouraged, please don't! After
all, you can skip the theory and dive straight into the code. You are free to
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
  defrecord State, server: nil, name: "", to_go: 0

  ## Public API ##

  def start(event_name, delay) do
    :erlang.spawn __MODULE__, :init, [Process.self, event_name, delay]
  end

  def start_link(event_name, delay) do
    :erlang.spawn_link __MODULE__, :init, [Process.self, event_name, delay]
  end

  def init(server, event_name, delay) do
    main_loop State.new server: server, name: event_name, to_go: datetime_to_seconds(delay)
  end
```

First, we define a record type named `Event.State`. In it we will store all the
state required for the event to run and contact the server when its time has
run out. Notice how the record type automatically inherits the name from its
parent module, so a nested record type `Record` in module `Module` will always
have the name `Module.Record` when used outside of the module. But for internal
use it can be referenced by its local name which in our case is simply `State`.

Elixir's `Process` module contains functions that are commonly used when
dealing with processes. Functions such as linking to a process, registering a
process, creating a monitor, getting access to the process' local dictionary —
all of those live in the `Process` module, the documented source code for which
is available [here][12].

The first three functions are responsible for spawning a new event process and
initializing the state with the data provided by the caller. Here we call
Erlang's `spawn` and `spawn_link` functions directly purely for demonstrational
purposes. Elixir provides equivalent built-in functions.

`__MODULE__` is one of Elixir's read-only pseudo-variables. Similarly to
Erlang's `?MODULE`, it expands to the current module's name at compile time.
The other pseudo-variables in Elixir are

* `__FUNCTION__` — returns a tuple representing the current function by name and arity or nil;
* `__LINE__` — returns an integer representing the current line;
* `__FILE__` — returns a string representing the current file;
* `__MAIN__` — the main namespace where modules are stored. For instance, `List` can also be accessed as `__MAIN__.List`;
* `__LOCAL__` — works as a proxy to force a function call to resolve locally (and not be expanded as a macro).

In the `init` function we create a new `State` record passing initial values as
an orddict. If you prefer a more formal syntax, you could rewrite it in one of
the following ways:

```elixir
State.new [server: server, name: event_name, to_go: delay]
# or
State.new([server: server, name: event_name, to_go: delay])
```

Note, however, that you cannot pass a list of tuples, because `new` expects an
orddict (which is an _ordered_ list of tuples). When it doesn't introduce
ambiguity, it is recommended to use the first approach.

The last thing of note here is the fact that we call the `datetime_to_seconds`
function passing it the given delay. This is done in order to accept the delay
both in seconds as well as in Erlang's datetime format. You can find the
definition of the `datetime_to_seconds` function at the end of the `Event`
module.

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
    match: { :DOWN, ^mon, :process, ^pid, _reason }
      # The server is down. We're ok with that.
      :ok
    end
  end
```

This is done by sending a `:cancel` message to the event process which is then
received in the main loop. If we look closely at the `main_loop` function
below, we'll see that all it does is hang waiting for the `:cancel` message to
arrive. Once it receives the message, it simply returns `:ok` and exists the
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
      server <- { ref, :ok }

    after: state.to_go * 1000
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

Before running the code, we need to compile it. I have provided a Makefile for
convenience. Simply execute `make` from the project's root to compile the
source code for our modules.

Once the code is compiled, launch `iex` inside the project's directory, then
open the **test_event.exs** file and paste its contents into the running Elixir
shell. Make sure everything is working as expected: the `iex` process
successfully receives a `{ :done, "Event" }` message from the first spawned
event process. Then we create another event with a larger timeout value and
cancel it before the timeout runs out. Play around with it for a while,
spawning multiple events and using the provided `flush` function to check that
you receive reminders from the spawned events.

Once you're satisfied with the result, move on to the next section where we're
going to take a closer look at the event server.

## The EventServer Module ##

The `EventServer` module will be responsible for creating events and notifying
subscribed clients when an event is ready to be delivered. Don't forget to keep
a tab with the [Erlang book][3] open alongside this tutorial, it contains a detailed
explanation of the decisions we're making while writing the code for the
server.

Similarly to the `Event` module, our server will need to keep some state in
order to be of any use. Here we defined two record types: `EventServer.State`
and `EventServer.Event`:

```elixir
defmodule EventServer do
  # We need to keep a list of all pending events and subscribed clients
  defrecord State, events: [], clients: []

  # Event description
  defrecord Event, name: "", description: "", pid: nil, timeout: 0
```

In the `init` function, we're entering the main loop passing it a `State`
record. Here we're exploiting Elixir's support for default arguments in
functions to create a new state when `init` is called without arguments.

```elixir
  def init(state // State.new) do
    main_loop state
  end
```

The next couple of functions in `EventServer` don't introduce new concepts,
they simply wrap the messaging protocol used by the server in a neat API, so
we'll skip them. One thing I'd like to point out though, in the `listen`
function below, is that we can prepend argument and variable names with
underscore `_`. Because some of the variables are not used inside the match
body, the compiler would emit a warning if those variables did not start with
underscore. Alternatively, we could use a single underscore in place of a
variable name to ignore it completely.

```elixir
  def listen(delay) do
    receive do
    match: m = { :done, _name, _description }
      [m | listen(0)]
    after: delay * 1000
      []
    end
  end
```

---

Now, let's take a look at the server's main loop which is pretty large,
although its basic structure is rather simple. Here's what its skeleton looks
like:

```elixir
  def main_loop(state) do
    receive do
    match: { pid, msg_ref, {:subscribe, client} }
      # Subscribe a client identified by the `pid`
      # ...
      pid <- { msg_ref, :ok }
      main_loop new_state

    match: { pid, msg_ref, {:add, name, description, timeout} }
      # Spawn a new event process to handle the :add request from client
      # ...
      pid <- { msg_ref, :ok }
      main_loop new_state

    match: { pid, msg_ref, {:cancel, name} }
      # Tear down the event process corresponding to `name`
      # ...
      pid <- { msg_ref, :ok }
      main_loop new_state

    match: { :done, name }
      # The event has finished, notify all clients
      # ...
      main_loop new_state

    match: :shutdown
      # Shut down the server and all living event processes
      exit :shutdown

    match: { :DOWN, ref, :process, _pid, _reason }
      # A client has crashed. Remove it from our subscribers list.
      # ...
      main_loop new_state

    match: :code_change
      # New code has arrived! Time to upgrade.
      #
      # The upgrade process is performed by using the qualified name
      # __MODULE__.init. Calling 'main_loop' instead would continue running the
      # old code. We can't to a call __MODULE__.main_loop, because 'main_loop'
      # is a private function. For this reason, we're doing a recursive call
      # through the 'init' function.
      __MODULE__.init state

    match: else
      # Someone sent us a message we don't understand
      IO.puts "Unknown message: #{inspect else}"
      main_loop state
    end
```

The basic pattern is as follows: enter the `receive` block waiting for a
message. Once a message has arrived, perform appropriate actions and make a
recursive call with the updated state into the same message loop. To see
exactly what actions are being performed and why, read carefully through the
explanation in the book and take a look at the code in the **event_server.ex**
file.

In the source code for our server you'll find another example of using Erlang
modules — we use the `orddict` module for book-keeping of clients and events.
Elixir currently provides the `Keyword` module that can only have atoms as
keys, so we're better off using Erlang's native `orddict` module for the time
being.

---

Lastly, we have a private function that broadcasts a message to all subscribed
clients:

```elixir
  # Send 'msg' to each subscribed client
  def send_to_clients(msg, clients) do
    Enum.map clients, fn({_ref, pid}) ->
      pid <- msg
    end
  end
```

`Enum` is a new module in Elixir, it provides common functions that deal will
collections such as `map`, `filter`, `all?`, `split`, etc. Take a look at its
[source code][11] which is heavily documented.

## Testing The Server ##

As with the `Event` module, I've written a small test-script to check that the
server works properly. It is located in the **test_server.exs** file. As before,
start up `iex` in the project's directory and copy the file contents into the
shell.

The next step you might take is walk through the code yourself, it is
abundantly commented. Every time you stumble upon an unfamiliar concept, try
playing with it in the shell and see what happens.

There is also a rudimentary supervisor implemented in the **event_sup.ex** file
that can launch the server as its child process and restart it in case of a
crash.

## Hot Code Swapping ##

One more thing I'd like to mention is how we can test hot code swapping in a
running application. Compile the source code as before and start up `iex` in
the project's root directory. Copy the contents of the **test_server.exs** file
into the shell once again so that we have a server instance running.

Now open another terminal tab or window and navigate to the project's root. Make
some change in the code, for instance, change the message the server sends in
response to an `:add` request. This is line 120 in the **event_server.ex** file.
Here's what mine looks like after the change:

```elixir
pid <- { msg_ref, :sir_yes_sir }
```

Then you need to recompile the source by invoking

    make

Now go back to the Terminal tab you have `iex` running in and evaluate the following expressions:

```elixir
# Ask Erlang to reload our EventServer module
:code.load_file EventServer
#=> {:module,EventServer}

EventServer.add_event "1", "", 1000
#=> :ok

# The new code is now loaded, but our server process is still running the old
# one. We need to tell it that it should make a qualified call to the `main_loop`
# function in order to upgrade to the newest available version of the module.
EventServer <- :code_change
#=> :code_change

# Make sure the code has been reloaded
EventServer.add_event "New event", "No description", 100
#=> :sir_yes_sir
```

That's it! You have just successfully updated the code of a running program.
Wasn't it fun?

## Where to go Next ##

Congratulations! You now have quite a solid understanding of what it takes to
write a full-blown client-server application using Elixir. Now you're ready to
start working on your own project or join efforts with the community and help
out a project in need. Visit the **#elixir-lang** channel on
**irc.freenode.net** and join the [mailing list][8] to keep in touch.

Good luck and have fun!


  [1]: http://elixir-lang.org/getting_started/1.html
  [2]: http://elixir-lang.org/
  [3]: http://learnyousomeerlang.com/designing-a-concurrent-application
  [4]: https://gist.github.com/2783092
  [5]: http://learnyousomeerlang.com/
  [6]: https://github.com/alco/elixir/wiki/Erlang-Syntax:-A-Crash-Course
  [7]: http://learnyousomeerlang.com/the-hitchhikers-guide-to-concurrency
  [8]: http://groups.google.com/group/elixir-lang-core
  [9]: http://www.erlang.org/course/concurrent_programming.html
  [10]: http://www.erlang.org/doc/getting_started/users_guide.html
  [11]: https://github.com/elixir-lang/elixir/blob/master/lib/enum.ex
  [12]: https://github.com/elixir-lang/elixir/blob/master/lib/process.ex
  [15]: http://elixir-lang.org/getting_started/7.html
