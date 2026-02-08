import psycopg2
import os

class PostGISClient:
    def __init__(self):
        self.conn = psycopg2.connect(
            host=os.getenv("POSTGRES_HOST", "postgis"),
            port=os.getenv("POSTGRES_PORT", 5432),
            dbname=os.getenv("POSTGRES_DB", "citybrain"),
            user=os.getenv("POSTGRES_USER", "postgres"),
            password=os.getenv("POSTGRES_PASSWORD", "postgres")
        )

    def query(self, sql: str, params=None):
        with self.conn.cursor() as cur:
            cur.execute(sql, params or [])
            cols = [desc[0] for desc in cur.description]
            return [dict(zip(cols, row)) for row in cur.fetchall()]

    def close(self):
        self.conn.close()
