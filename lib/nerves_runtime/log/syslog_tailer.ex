defmodule Nerves.Runtime.Log.SyslogTailer do
  use GenServer
  require Logger

  @moduledoc """
  This GenServer routes syslog messages from C-based applications and libraries through
  the Elixir Logger for collection.
  """

  alias Nerves.Runtime.Log.SyslogParser

  @syslog_path "/dev/log"

  @doc """
  Start the local syslog GenServer.
  """
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(opts) do
    # Blindly try to remove an old file just in case it exists from a previous run
    _ = File.rm(@syslog_path)

    {:ok, log_port} =
      :gen_udp.open(0, [:local, :binary, {:active, true}, {:ip, {:local, @syslog_path}}])

    # All processes should be able to log messages
    File.chmod!(@syslog_path, 0o666)

    log_level = Keyword.get(opts, :log_level) |> SyslogParser.severity_code()

    {:ok, %{log_port: log_port, log_level: log_level}}
  end

  @impl GenServer
  def handle_info({:udp, log_port, _, 0, raw_entry}, state = %{log_port: log_port, log_level: log_level}) do
    case SyslogParser.parse(raw_entry) do
      {:ok, %{facility: facility, severity: severity, message: message}} ->
        if severity <= log_level do
          level = SyslogParser.severity_to_logger(severity)

          Logger.bare_log(
            level,
            message,
            module: __MODULE__,
            facility: facility,
            severity: severity
          )
        end

      _ ->
        # This is unlikely to ever happen, but if a message was somehow
        # malformed and we couldn't parse the syslog priority, we should
        # still do a best-effort to pass along the raw data.
        Logger.warn("Malformed syslog report: #{inspect(raw_entry)}")
    end

    {:noreply, state}
  end
end
