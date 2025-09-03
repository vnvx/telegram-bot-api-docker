# build stage
FROM debian:bookworm as builder

RUN apt-get update &&     apt-get install -y --no-install-recommends     build-essential     cmake     git     gperf     libssl-dev     zlib1g-dev &&     rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/
RUN git clone --recursive https://github.com/tdlib/telegram-bot-api.git
WORKDIR /usr/src/telegram-bot-api
RUN mkdir -p build
WORKDIR /usr/src/telegram-bot-api/build
RUN cmake -DCMAKE_BUILD_TYPE=Release ..
RUN cmake --build . --target install

# final stage
FROM debian:bookworm

RUN apt-get update &&     apt-get install -y --no-install-recommends     libssl-dev     zlib1g-dev &&     rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/telegram-bot-api /usr/local/bin/telegram-bot-api

WORKDIR /var/lib/telegram-bot-api

EXPOSE 8081

ENTRYPOINT ["telegram-bot-api"]
