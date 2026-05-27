FROM docker:27-cli AS docker-cli

FROM nousresearch/hermes-agent:latest

USER root
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
RUN apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /usr/local/libexec/docker/cli-plugins
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/libexec/docker/cli-plugins/docker-compose
RUN .venv/bin/uv pip install synadia-ai-agents synadia-ai-agent-service nkeys
USER hermes
