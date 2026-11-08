# syntax=docker/dockerfile:1.7

# ---------------------------------------------------------------------------
# Stage 1 - build a self-contained OTP release
# ---------------------------------------------------------------------------
ARG ELIXIR_VERSION=1.17.2
ARG OTP_VERSION=27.0.1
ARG ALPINE_VERSION=3.20.2

ARG BUILDER_IMAGE=hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION}
ARG RUNNER_IMAGE=alpine:${ALPINE_VERSION}

FROM ${BUILDER_IMAGE} AS builder

# build-base + git are only needed while dependencies and the release compile.
RUN apk add --no-cache build-base git

WORKDIR /app

ENV MIX_ENV=prod \
    LANG=C.UTF-8

RUN mix local.hex --force && \
    mix local.rebar --force

# Cache the dependency graph independently of the application source.
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

RUN mkdir config
COPY config/config.exs config/prod.exs config/runtime.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY rel rel

RUN mix compile
RUN mix assets.deploy
RUN mix release

# Windows build contexts do not preserve the executable bit, so the generated
# boot overlay is normalised explicitly here.
RUN chmod +x _build/prod/rel/meetcutes/bin/server

# ---------------------------------------------------------------------------
# Stage 2 - minimal runtime image
# ---------------------------------------------------------------------------
FROM ${RUNNER_IMAGE} AS runner

RUN apk add --no-cache \
      ca-certificates \
      libstdc++ \
      ncurses-libs \
      openssl

WORKDIR /app

ENV LANG=C.UTF-8 \
    HOME=/tmp \
    ERL_CRASH_DUMP=/tmp/erl_crash.dump \
    PHX_SERVER=true

# Copy only the assembled release, never the build toolchain or source.
COPY --from=builder /app/_build/prod/rel/meetcutes ./

USER nobody

EXPOSE 4000

CMD ["./bin/server"]
