FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt ./
RUN pip install -r requirements.txt

COPY main.py poller.py sources.py telegram.py judge.py stats.py release-sources.txt ./
COPY static ./static

FROM base AS test

COPY requirements-dev.txt ./
RUN pip install -r requirements-dev.txt
COPY pytest.ini conftest.py ./
COPY tests ./tests
RUN python -m pytest && touch /app/tests-passed

FROM base AS runtime

COPY --from=test /app/tests-passed ./tests-passed

EXPOSE 8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080", "--proxy-headers", "--forwarded-allow-ips", "*"]
