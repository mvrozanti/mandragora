FROM python:3.12-alpine

WORKDIR /app
COPY . /app

ENV PORT=8080 \
    FOOD_DATA_DIR=/data

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["python", "server.py"]
