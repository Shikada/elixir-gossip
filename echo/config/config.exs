import Config

config :logger, :default_handler, false
config :logger, level: :debug
config :echo, :logger, [
  {:handler, :file_log, :logger_std_h,
   %{
     config: %{
       type: :file,
       file: ~c"/home/shikada/code/fly_distributed_systems/echo/bla.log",
       filesync_repeat_interval: 5000,
       file_check: 5000,
       max_no_bytes: 10_000_000,
       max_no_files: 5,
       compress_on_rotate: true
     },
     formatter: Logger.Formatter.new()
   }}
]
