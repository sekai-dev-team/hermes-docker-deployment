FROM docker/mcp-gateway:latest AS docker-mcp

FROM python:3.12-alpine

COPY --from=docker-mcp /docker-mcp /usr/local/bin/docker-mcp
COPY server.py /app/server.py

ENV PROFILE_ID=hermes-default
ENV CATALOG_REF=mcp/docker-mcp-catalog:latest
ENV ALLOWED_SERVERS=fetch
ENV DOCKER_MCP_IN_CONTAINER=1

ENTRYPOINT ["python3", "/app/server.py"]
