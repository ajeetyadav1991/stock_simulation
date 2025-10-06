#!/bin/bash
./scripts/run_backend.sh &
BACKEND_PID=$!
sleep 3
./scripts/run_frontend.sh &
FRONTEND_PID=$!
trap "kill $BACKEND_PID $FRONTEND_PID 2>/dev/null; exit" INT TERM
wait
