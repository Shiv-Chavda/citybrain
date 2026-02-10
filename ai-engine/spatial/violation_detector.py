import json
import os
import psycopg2

def detect_construction_hospital_violations():
    conn = psycopg2.connect(
    host=os.getenv("POSTGRES_HOST", "postgis"),
    port=os.getenv("POSTGRES_PORT", 5432),
    database=os.getenv("POSTGRES_DB", "citybrain"),
    user=os.getenv("POSTGRES_USER", "postgres"),
    password=os.getenv("POSTGRES_PASSWORD", "postgres")
)
    cur = conn.cursor()

    query = """
    SELECT
      c.id,
      c.risk_factor,
      h.name,
      b.buffer_type,
      ST_AsGeoJSON(c.geom),
      ROUND(ST_Distance(c.geom::geography, h.geom::geography)) AS distance
    FROM construction_projects c
    JOIN hospital_buffers b ON ST_Intersects(c.geom, b.geom)
    JOIN hospitals h ON h.id = b.hospital_id
    """

    cur.execute(query)
    rows = cur.fetchall()

    violations = []
    for r in rows:
        violations.append({
            "construction_id": r[0],
            "risk_factor": r[1],
            "hospital": r[2],
            "severity": r[3],
            "distance_m": r[5],
            "geometry": json.loads(r[4]),
        })

    cur.close()
    conn.close()
    return violations
