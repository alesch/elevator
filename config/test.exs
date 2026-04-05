import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :elevator, ElevatorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "gGCmB2RPBCP/eHiYZPyyu+4tBB/p/p0nJLbg/VQFFrcF/+SlbnHncjxeO0rV9H/t",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
# Disabling the hardware stack and server for unit tests 
# to allow isolated testing of functional modules.
config :elevator,
  hardware_stack_enabled: false

config :cabbage,
  features: "features/"
