FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt ./
RUN pip install -r requirements.txt

ARG PIPER_VOICES_BASE=https://huggingface.co/rhasspy/piper-voices/resolve/main
RUN mkdir -p /models && cd /models && \
    for v in \
      "en/en_US/lessac/medium/en_US-lessac-medium" \
      "pt/pt_BR/faber/medium/pt_BR-faber-medium" \
    ; do \
      name=$(basename "$v"); \
      curl -fsSL "${PIPER_VOICES_BASE}/${v}.onnx" -o "${name}.onnx"; \
      curl -fsSL "${PIPER_VOICES_BASE}/${v}.onnx.json" -o "${name}.onnx.json"; \
    done

COPY main.py ./
COPY static ./static

EXPOSE 8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080", "--proxy-headers", "--forwarded-allow-ips", "*"]
