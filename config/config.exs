import Config

config :ea, default_backend: {Ea.Backends.SimpleBackend, name: Ea.DefaultSimpleBackendInstance}
config :ea, time: Ea.Time

import_config "#{config_env()}.exs"
