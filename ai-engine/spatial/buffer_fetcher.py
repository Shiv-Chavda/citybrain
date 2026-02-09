import psycopg2
import json
import os

def _get_postgis_conn():
  return psycopg2.connect(
    host=os.getenv("POSTGRES_HOST", "postgis"),
    port=int(os.getenv("POSTGRES_PORT", 5432)),
    dbname=os.getenv("POSTGRES_DB", "citybrain"),
    user=os.getenv("POSTGRES_USER", "citybrain"),
    password=os.getenv("POSTGRES_PASSWORD", "citybrain")
  )

def fetch_hospital_buffers(distance_meters: int):
    conn = _get_postgis_conn()
    cur = conn.cursor()

    cur.execute(f"""
        SELECT
          id,
          ST_AsGeoJSON(
            ST_Transform(
              ST_Buffer(
                ST_Transform(geom, 3857),
                %s
              ),
              4326
            )
          )
        FROM hospitals
        LIMIT 50;
    """, (distance_meters,))

    rows = cur.fetchall()
    cur.close()
    conn.close()

    return [
        {
            "id": r[0],
            "geometry": json.loads(r[1])
        }
        for r in rows if r[1] is not None
    ]
