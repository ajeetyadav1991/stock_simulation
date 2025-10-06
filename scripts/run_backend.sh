#!/bin/bash
cd backend
source venv/bin/activate
export $(cat ../.env | xargs)
uvicorn main:app --reload --host 0.0.0.0 --port 8000
