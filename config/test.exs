import Config

config :ea, default_backend: {Ea.BackendMock, some_opt: :some_value}
config :ea, time: Ea.TimeMock
