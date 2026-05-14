FROM docker:27-cli AS docker-cli

FROM nousresearch/hermes-agent:latest

USER root
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
RUN mkdir -p /usr/local/libexec/docker/cli-plugins
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/libexec/docker/cli-plugins/docker-compose
USER hermes
