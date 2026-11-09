FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl build-essential bc bison flex libelf-dev \
    pkg-config rsync kmod \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /work
ENTRYPOINT ["/bin/bash", "/build.sh"]
