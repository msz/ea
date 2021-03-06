import Config

config :ea, default_backend: {Ea.Backends.AgentBackend, name: Ea.DefaultAgentBackendInstance}
config :ea, time: Ea.Time

import_config "#{config_env()}.exs"
