import Config

config :nostrum,
  token: System.fetch_env!("DISCORD_TOKEN"),
  gateway_intents: :all,
  ffmpeg: nil
