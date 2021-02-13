import Config

config :ea, default_backend: {BackendMock, some_opt: :some_value}

import_config "#{config_env()}.exs"
