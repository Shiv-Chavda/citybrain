FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y gcc libpq-dev && rm -rf /var/lib/apt/lists/*

COPY main.py /app/main.py

RUN pip install fastapi uvicorn psycopg2-binary neo4j

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001"]
