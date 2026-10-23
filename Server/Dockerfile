FROM python:3.12.15-slim-trixie@sha256:a0f57064cbdcd6285fa45f51237ab0b35ea8ebaed06a1f5973e89e19dfb86704
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
COPY requirements.txt ./
RUN pip install --no-cache-dir --no-compile --only-binary=:all: -r requirements.txt \
    && groupadd --gid 10001 nianbox \
    && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin nianbox \
    && mkdir /data && chown nianbox:nianbox /data
COPY nianbox ./nianbox
LABEL org.opencontainers.image.title="NianBox Server" \
      org.opencontainers.image.description="Single-user SQLite REST and MCP memory inbox" \
      org.opencontainers.image.source="https://github.com/takboo/nianbox" \
      org.opencontainers.image.licenses="MIT"
USER 10001:10001
VOLUME /data
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)"
CMD ["uvicorn", "nianbox.app:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
