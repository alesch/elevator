import Config

config :elevator, ElevatorWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ElevatorWeb.ErrorHTML, json: ElevatorWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Elevator.PubSub,
  live_view: [signing_salt: "v8I/Xn3X"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :elevator, 
  hardware_stack_enabled: true

import_config "#{config_env()}.exs"

