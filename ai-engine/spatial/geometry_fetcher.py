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

def fetch_geometries(entity_type: str):
    conn = _get_postgis_conn()
    cur = conn.cursor()

    if entity_type == "hospital":
        cur.execute("""
            SELECT id, ST_AsGeoJSON(geom)
            FROM hospitals
            WHERE geom IS NOT NULL
            LIMIT 500;
        """)
    elif entity_type == "road":
        cur.execute("""
            SELECT id, ST_AsGeoJSON(geom)
            FROM roads
            WHERE geom IS NOT NULL
            LIMIT 500;
        """)
    else:
        raise ValueError("Unsupported entity")

    rows = cur.fetchall()
    cur.close()
    conn.close()

    return [
        {
            "type": "Feature",
            "geometry": json.loads(r[1]),
            "properties": {
                "id": r[0],
                "highlight": entity_type
            }
        }
        for r in rows
    ]
