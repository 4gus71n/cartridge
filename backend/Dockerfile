# Cartridge API + creator-portal checks worker + catalog publisher.
# Base image ships Chromium for Playwright (the boot check needs it).
FROM mcr.microsoft.com/playwright/python:v1.63.0-noble

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    DATABASE_URL=sqlite:////data/cartridge.db \
    CHECKS_DIR=/data/checks \
    CARTRIDGE_HOSTING_DIR=/hosting
WORKDIR /srv/backend
RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app ./app
COPY scripts ./scripts
COPY docker-entrypoint.sh /usr/local/bin/
VOLUME ["/data", "/hosting"]
EXPOSE 8123
HEALTHCHECK --interval=30s --timeout=5s CMD python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8123/health',timeout=4)"
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8123"]
