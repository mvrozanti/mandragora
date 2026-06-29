for i in $(seq 1 30); do
  curl -fsS http://100.115.80.79:11434/api/version >/dev/null && break
  sleep 1
done
exec curl -fsS --no-buffer -X POST http://100.115.80.79:11434/api/pull \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\",\"stream\":false}"
