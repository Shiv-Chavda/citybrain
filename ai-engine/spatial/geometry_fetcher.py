import psycopg2
import json

POSTGIS_DSN = "dbname=citybrain user=citybrain password=citybrain host=postgis"

def fetch_geometries(entity_type: str):
    conn = psycopg2.connect(POSTGIS_DSN)
    cur = conn.cursor()

    if entity_type == "hospital":
        query = """
        SELECT id, ST_AsGeoJSON(geom)
        FROM hospitals
        LIMIT 50;
        """
    elif entity_type == "road":
        query = """
        SELECT id, ST_AsGeoJSON(geom)
        FROM roads
        LIMIT 50;
        """
    else:
        return []

    cur.execute(query)
    rows = cur.fetchall()

    cur.close()
    conn.close()

    return [
        {
            "id": r[0],
            "geometry": json.loads(r[1])
        }
        for r in rows
    ]
