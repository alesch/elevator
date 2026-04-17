import Config

config :elevator, ElevatorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  server: true

config :logger, level: :warning

config :elevator,
  hardware_stack_enabled: true,
  e2e_routes: true
