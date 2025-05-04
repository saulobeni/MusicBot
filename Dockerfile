FROM elixir:1.18.3-alpine

WORKDIR /usr/src/music_bot

COPY . .

RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get

CMD ["iex", "-S", "mix"]
