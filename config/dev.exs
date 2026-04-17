import Config

config :elevator, ElevatorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  watchers: []

config :elevator, dev_routes: true

# Enable helpful, but potentially expensive runtime checks
config :phoenix, :enable_expensive_runtime_checks, true
