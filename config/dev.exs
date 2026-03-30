import Config

config :elevator, ElevatorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "gGCmB2RPBCP/eHiYZPyyu+4tBB/p/p0nJLbg/VQFFrcF/+SlbnHncjxeO0rV9H/t",
  watchers: []

config :elevator, dev_routes: true

# Enable helpful, but potentially expensive runtime checks
config :phoenix, :enable_expensive_runtime_checks, true
