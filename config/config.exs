import Config

if Mix.env() == :dev do
  config :elixord, testing: true
end
