curl -X POST http://localhost:8080/post \
  -H 'Content-Type: application/json' \
  -d '{"operation":"read_status","service":"risk-engine"}'
