import Config

# Configures the endpoint
config :elevator, ElevatorWeb.Endpoint,
  url: [host: "example.com", port: 80],
  cache_static_manifest: "priv/static/cache_manifest.json"

# Configures Elixir's Logger
config :logger, level: :info
