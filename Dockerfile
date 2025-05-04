FROM elixir:1.14-alpine AS build

# Install build dependencies
RUN apk add --no-cache build-base git

# Prepare build dir
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV=prod

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/$MIX_ENV.exs config/
RUN mix deps.compile

# Copy priv and compile assets
COPY priv priv
COPY lib lib
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

# Release
RUN mix release

# Prepare release image
FROM alpine:3.16 AS app
RUN apk add --no-cache libstdc++ openssl ncurses-libs bash

WORKDIR /app

RUN chown nobody:nobody /app

USER nobody:nobody

COPY --from=build --chown=nobody:nobody /app/_build/prod/rel/music_bot ./

ENV HOME=/app
ENV MIX_ENV=prod

CMD ["bin/music_bot", "start"]