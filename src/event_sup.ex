defmodule EventSup do
  @moduledoc """
  This is a simple supervisor that will monitor the health of its child process
  and restart it in case of a crash.
  """

  def start(mod, args) do
    spawn __MODULE__, :init, [{mod, args}]
  end

  def start_link(mod, args) do
    spawn_link __MODULE__, :init, [{mod, args}]
  end

  def init({mod, args}) do
    :erlang.process_flag :trap_exit, true
    main_loop {mod, :start_link, args}
  end

  defp main_loop({m, f, a}) do
    pid = apply m, f, a
    receive do
    match: {:EXIT, _from, :shutdown}
      exit :shutdown  # will kill the child too
    match: {:EXIT, ^pid, reason}
      IO.puts "Process #{inspect pid} exited for reason #{inspect reason}"
      main_loop {m, f, a}
    end
  end
end
