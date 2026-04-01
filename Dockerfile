# Stage 1: Build the release
FROM hexpm/elixir:1.15.2-erlang-26.0.2-alpine-3.18.3 AS builder

# install build dependencies
RUN apk add --no-cache build-base git

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before compiling dependencies
# so any change to them will only recompile the affected dependencies
COPY config/config.exs config/prod.exs ./config/
RUN mix deps.compile

COPY lib lib
COPY priv priv

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

RUN mix release

# Stage 2: Final runtime image
FROM alpine:3.18.3 AS runner

RUN apk add --no-cache libstdc++ ncurses-libs openssl

WORKDIR "/app"
RUN chown nobody:nobody /app

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:nobody /app/_build/prod/rel/elevator ./

ENV MIX_ENV="prod"

# Start the Phoenix app
CMD ["/app/bin/elevator", "start"]
