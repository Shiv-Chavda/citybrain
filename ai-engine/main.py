import json
from rag.ingest import ingest_pdfs
from rag.query import rag_query
from spatial.geometry_fetcher import fetch_geometries
from spatial.geojson import to_feature_collection
from spatial.buffer_fetcher import fetch_hospital_buffers
from spatial.geojson import to_feature_collection
from spatial.violation_detector import detect_construction_hospital_violations
from rag.schemas import RagAnswer
from fastapi.middleware.cors import CORSMiddleware
from fastapi import FastAPI
from neo4j import GraphDatabase
import psycopg2

import os
from typing import List, Optional, Literal
from pydantic import BaseModel

class GraphEntity(BaseModel):
    id: str
    type: Literal["Road", "Hospital", "Zone"]
    hop: int
    geometry: Optional[list] = None
    location: Optional[list] = None

class ImpactSubgraphResponse(BaseModel):
    root: str
    max_hops: int
    subgraph: List[GraphEntity]

class ZoneImpact(BaseModel):
    zone_id: int
    zone_name: str
    affected_roads: int
    total_roads: int
    severity: float
    geometry: list


app = FastAPI(title="CityBrain Graph Engine")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # allow Flutter web
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


NEO4J_URI = os.getenv("NEO4J_URI", "bolt://neo4j:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASS = os.getenv("NEO4J_PASSWORD", os.getenv("NEO4J_PASS", "password"))

PG_HOST = os.getenv("POSTGRES_HOST", "postgis")
PG_PORT = int(os.getenv("POSTGRES_PORT", 5432))
PG_DB = os.getenv("POSTGRES_DB", "citybrain")
PG_USER = os.getenv("POSTGRES_USER", "citybrain")
PG_PASS = os.getenv("POSTGRES_PASSWORD", "citybrain")

driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASS))
pg_conn = psycopg2.connect(
    host=PG_HOST,
    port=PG_PORT,
    database=PG_DB,
    user=PG_USER,
    password=PG_PASS
)

def get_pg_conn():
    return psycopg2.connect(
        host=PG_HOST,
        port=PG_PORT,
        database=PG_DB,
        user=PG_USER,
        password=PG_PASS
    )

def build_junctions():
    print("Building Junction nodes")

    cur = pg_conn.cursor()
    cur.execute("""
        SELECT id, ST_Y(geom), ST_X(geom)
        FROM road_junctions
    """)
    rows = cur.fetchall()

    with driver.session() as session:
        session.run("MATCH (j:Junction) DETACH DELETE j")

        for jid, lat, lon in rows:
            session.run("""
                MERGE (j:Junction {id: $id})
                SET j.lat = $lat,
                    j.lon = $lon
            """, id=jid, lat=float(lat), lon=float(lon))

    cur.close()
    print(f"Inserted {len(rows)} Junctions")

def link_roads_to_junctions():
    print("Linking Roads to Junctions")

    cur = pg_conn.cursor()
    cur.execute("""
        SELECT
          j.id,
          r.osm_id
        FROM road_junctions j
        JOIN planet_osm_roads r
          ON ST_DWithin(j.geom, r.way, 0.00005)
    """)
    rows = cur.fetchall()

    with driver.session() as session:
        session.run("MATCH ()-[r:MEETS_AT]->() DELETE r")

        for jid, road_id in rows:
            session.run("""
                MATCH (j:Junction {id: $jid})
                MATCH (r:Road {osm_id: $rid})
                MERGE (r)-[:MEETS_AT]->(j)
            """, jid=jid, rid=int(road_id))

    cur.close()
    print(f"Linked {len(rows)} road–junction pairs")

def rebuild_real_construction_projects():
    print("Rebuilding REAL ConstructionProject nodes from OSM")

    cur = pg_conn.cursor()
    cur.execute("""
        SELECT id, name, project_type, risk_factor
        FROM construction_projects
    """)
    rows = cur.fetchall()

    with driver.session() as session:
        session.run("MATCH (c:ConstructionProject) DETACH DELETE c")

        for cid, name, ptype, risk in rows:
            session.run("""
                MERGE (c:ConstructionProject {id: $id})
                SET c.name = $name,
                    c.type = $type,
                    c.risk_factor = $risk
            """, id=cid, name=name, type=ptype, risk=float(risk))

    cur.close()
    print(f"Inserted {len(rows)} REAL construction projects")


def link_real_construction_to_roads():
    print("Linking REAL Construction Projects to Roads")

    cur = pg_conn.cursor()
    cur.execute("""
        SELECT project_id, road_osm_id
        FROM construction_road_links
    """)
    rows = cur.fetchall()

    with driver.session() as session:
        session.run("MATCH ()-[r:AFFECTS]->() DELETE r")

        for pid, rid in rows:
            session.run("""
                MATCH (c:ConstructionProject {id: $pid})
                MATCH (r:Road {osm_id: $rid})
                MERGE (c)-[:AFFECTS {severity: c.risk_factor}]->(r)
            """, pid=pid, rid=int(rid))

    cur.close()
    print(f"Linked {len(rows)} REAL construction-road pairs")

def build_road_zone_links():
    print("Linking Road -> Zone using PostGIS spatial join")

    conn = psycopg2.connect(
        host=PG_HOST,
        port=PG_PORT,
        database=PG_DB,
        user=PG_USER,
        password=PG_PASS
    )
    cur = conn.cursor()

    cur.execute("""
        DROP TABLE IF EXISTS road_zone_links;
        CREATE TABLE road_zone_links (
            road_osm_id BIGINT,
            zone_osm_id BIGINT
        );
    """)

    cur.execute("""
        INSERT INTO road_zone_links (road_osm_id, zone_osm_id)
        SELECT 
            r.osm_id,
            z.osm_id
        FROM planet_osm_line r
        JOIN planet_osm_polygon z
          ON ST_Intersects(r.way, z.way)
        WHERE z.admin_level IN ('5','6');
    """)

    cur.execute("SELECT COUNT(*) FROM road_zone_links;")
    count = cur.fetchone()[0]

    conn.commit()
    cur.close()
    conn.close()

    print(f"Found {count} Road-Zone spatial intersections")
    return {"pairs": count}


def rebuild_roads_from_postgis_to_neo4j():
    print("Rebuilding Road nodes from PostGIS into Neo4j")
    pg = pg_conn
    cur = pg.cursor()

    cur.execute("""
        SELECT osm_id
        FROM planet_osm_roads
        WHERE osm_id IS NOT NULL
    """)
    roads = cur.fetchall()

    with driver.session() as session:
        session.run("MATCH (r:Road) DETACH DELETE r")

        for (osm_id,) in roads:
            session.run(
                "MERGE (:Road {osm_id: $id})",
                id=int(osm_id)
            )

    print(f"Inserted {len(roads)} Road nodes into Neo4j")


def rebuild_zones_from_postgis():
    print("Rebuilding Zone nodes from PostGIS")
    pg = pg_conn
    cur = pg.cursor()

    cur.execute("""
        SELECT
            CAST(osm_id AS BIGINT) AS zone_id,
            name,
            ST_Area(way) AS area
        FROM planet_osm_polygon
        WHERE boundary = 'administrative'
          AND admin_level IN ('6','7','8')
          AND osm_id IS NOT NULL
          AND name IS NOT NULL
    """)

    zones = cur.fetchall()

    with driver.session() as session:
        session.run("MATCH (z:Zone) DETACH DELETE z")

        for zone_id, name, area in zones:
            session.run(""" 
                MERGE (z:Zone {zone_id: $zone_id})
                SET z.name = $name,
                    z.area = $area
            """, zone_id=int(zone_id), name=name, area=float(area))

    print(f"Inserted {len(zones)} Zones into Neo4j")



def build_road_connectivity_from_postgis():
    pg = pg_conn
    cur = pg.cursor()
    neo = driver.session(database="neo4j")

    cur.execute("""
        SELECT r1.osm_id, r2.osm_id
        FROM planet_osm_roads r1
        JOIN planet_osm_roads r2
        ON ST_Touches(r1.way, r2.way)
        WHERE r1.osm_id <> r2.osm_id
        LIMIT 200000;
    """)

    for a, b in cur.fetchall():
        neo.run("""
            MATCH (r1:Road {osm_id: $a}), (r2:Road {osm_id: $b})
            MERGE (r1)-[:CONNECTS_TO]->(r2)
            MERGE (r2)-[:CONNECTS_TO]->(r1)
        """, a=int(a), b=int(b))

    neo.close()
    cur.close()
    pg.close()

def corrected_push_road_zone_links_to_neo4j():
    print("Pushing Road → Zone relationships into Neo4j")

    pg = get_pg_conn()
    cur = pg.cursor()

    cur.execute("SELECT road_osm_id, zone_osm_id FROM road_zone_links;")
    pairs = cur.fetchall()
    print(f"Fetched {len(pairs)} Road–Zone pairs")
    with driver.session() as session:
        session.run("MATCH ()-[r:LOCATED_IN]->() DELETE r")

        for road_id, zone_id in pairs:
            session.run("""
                MATCH (r:Road {osm_id: $road})
                MATCH (z:Zone {zone_id: $zone})
                MERGE (r)-[:LOCATED_IN]->(z)
            """, road=int(road_id), zone=int(zone_id))

    cur.close()
    pg.close()
    print("Road → Zone relationships successfully written to Neo4j")
    return {"status": "Neo4j updated", "links": len(pairs)}


def push_road_zone_links_to_neo4j():
    print("Pushing Road → Zone relationships into Neo4j")

    pg = get_pg_conn()
    cur = pg.cursor()

    cur.execute("SELECT road_osm_id, zone_osm_id FROM road_zone_links;")
    pairs = cur.fetchall()
    print(f"Fetched {len(pairs)} Road–Zone pairs")

    with driver.session() as session:
        session.run("MATCH ()-[r:LOCATED_IN]->() DELETE r")

        for road_id, zone_id in pairs:
            session.run("""
                MATCH (r:Road {osm_id: $road})
                MATCH (z:Zone {id: $zone})
                MERGE (r)-[:LOCATED_IN]->(z)
            """, road=str(road_id), zone=str(zone_id))

    cur.close()
    pg.close()
    driver.close()

    print("Road → Zone relationships successfully written to Neo4j")
    return {"status": "Neo4j updated", "links": len(pairs)}

@app.get("/map/violations/construction-hospitals")
def construction_hospital_violations():
    return {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "geometry": v["geometry"],
                "properties": {
                    "construction_id": v["construction_id"],
                    "hospital": v["hospital"],
                    "severity": v["severity"],
                    "distance_m": v["distance_m"],
                    "risk_factor": v["risk_factor"]
                }
            }
            for v in detect_construction_hospital_violations()
        ]
    }

@app.get("/map/hospital-buffers")
def hospital_buffers_geojson():
    conn = pg_conn
    cur = conn.cursor()

    cur.execute("""
        SELECT jsonb_build_object(
          'type', 'FeatureCollection',
          'features', jsonb_agg(
            jsonb_build_object(
              'type', 'Feature',
              'geometry', ST_AsGeoJSON(geom)::jsonb,
              'properties', jsonb_build_object(
                'hospital', hospital_name,
                'buffer_type', buffer_type,
                'distance', distance_m
              )
            )
          )
        )
        FROM hospital_buffers;
    """)

    return cur.fetchone()[0]


@app.get("/api/impact/junction/{junction_id}")
def junction_impact(junction_id: int):
    with driver.session() as neo:
        res = neo.run("""
        MATCH (j:Junction {id: $jid})<-[:MEETS_AT]-(r:Road)
        RETURN r.osm_id AS road_id
        """, jid=junction_id)

        roads = [r["road_id"] for r in res]

    return {
        "junction_id": junction_id,
        "connected_roads": roads,
        "severity": len(roads)
    }

@app.get("/api/impact/construction/{road_id}")
def construction_impact(road_id: int):
    with driver.session() as neo:
        res = neo.run("""
        MATCH (c:ConstructionProject)-[a:AFFECTS]->(r:Road {osm_id: $rid})
        RETURN
          c.name AS project,
          a.severity AS severity
        """, rid=road_id)

        projects = list(res)

    return {
        "road_id": road_id,
        "projects": projects,
        "risk_level": "HIGH" if projects else "LOW"
    }

@app.get("/map/buffer/hospitals")
def hospital_buffers(distance: int = 100):
    buffers = fetch_hospital_buffers(distance)
    return to_feature_collection(
        buffers,
        properties={
            "type": "hospital_buffer",
            "distance_m": distance
        }
    )

@app.get("/map/highlight")
def map_highlight(entity: str):
    features = fetch_geometries(entity)

    return {
        "type": "FeatureCollection",
        "features": features
    }

@app.post("/build/roads")
def build_roads():
    cur = pg_conn.cursor()
    cur.execute("""
        SELECT osm_id, name, highway, ST_Length(way::geography)
        FROM planet_osm_roads
        WHERE highway IS NOT NULL;
    """)
    roads = cur.fetchall()

    with driver.session(database="neo4j") as session:
        for r in roads:
            session.run("""
                MERGE (road:Road {id: $id})
                SET road.name = $name,
                    road.type = $type,
                    road.length = $length
                MERGE (city:City {id: "ahmedabad"})
                MERGE (road)-[:LOCATED_IN]->(city)
            """, id=str(r[0]), name=r[1], type=r[2], length=float(r[3]))

    return {"status": "Road nodes created", "count": len(roads)}

@app.post("/build/road-connections")
def connect_roads():
    cur = pg_conn.cursor()
    cur.execute("""
        SELECT r1.osm_id, r2.osm_id
        FROM planet_osm_roads r1
        JOIN planet_osm_roads r2
        ON ST_Touches(r1.way, r2.way)
        WHERE r1.osm_id <> r2.osm_id;
    """)
    pairs = cur.fetchall()

    with driver.session(database="neo4j") as session:
        for a, b in pairs:
            session.run("""
                MATCH (r1:Road {id: $a}), (r2:Road {id: $b})
                MERGE (r1)-[:CONNECTS_TO]->(r2)
            """, a=str(a), b=str(b))

    return {"status": "Road connectivity created", "edges": len(pairs)}

@app.post("/build/zones")
def build_zones():
    cur = pg_conn.cursor()
    cur.execute("""
        SELECT osm_id, name, ST_Area(way::geography)
        FROM planet_osm_polygon
        WHERE boundary = 'administrative';
    """)
    zones = cur.fetchall()

    with driver.session(database="neo4j") as session:
        for z in zones:
            session.run("""
                MERGE (zone:Zone {id: $id})
                SET zone.name = $name,
                    zone.area = $area
                MERGE (city:City {id: "ahmedabad"})
                MERGE (zone)-[:PART_OF]->(city)
            """, id=str(z[0]), name=z[1], area=float(z[2]))

    return {"status": "Zones created", "count": len(zones)}


@app.post("/link_roads_to_zones")
def link_roads_to_zones():
    cur = pg_conn.cursor()
    cur.execute("""
        SELECT r.osm_id, z.osm_id
        FROM planet_osm_roads r, planet_osm_polygon z
        WHERE z.boundary = 'administrative'
        AND ST_Intersects(r.way, z.way);
    """)
    pairs = cur.fetchall()

    with driver.session(database="neo4j") as session:
        for r, z in pairs:
            session.run("""
                MATCH (road:Road {id: $rid}), (zone:Zone {id: $zid})
                MERGE (road)-[:LOCATED_IN]->(zone)
            """, rid=str(r), zid=str(z))

    return {"status": "Road-Zone links created", "edges": len(pairs)}


@app.post("/build_hospitals")
def build_hospitals():
    cur = pg_conn.cursor()
    cur.execute("""
        SELECT osm_id, name, way
        FROM planet_osm_point
        WHERE amenity = 'hospital';
    """)
    hospitals = cur.fetchall()

    with driver.session(database="neo4j") as session:
        for h in hospitals:
            session.run("""
                MERGE (hos:Hospital {id: $id})
                SET hos.name = $name
                MERGE (city:City {id: "ahmedabad"})
                MERGE (hos)-[:LOCATED_IN]->(city)
            """, id=str(h[0]), name=h[1])

    return {"status": "Hospitals created", "count": len(hospitals)}

@app.get("/impact/road/{road_id}")
def road_impact(road_id: str, hops: int = 2):
    with driver.session(database="neo4j") as session:
        result = session.run("""
            MATCH (r:Road {id: $rid})
            CALL apoc.path.subgraphAll(r, {maxLevel: $hops})
            YIELD nodes, relationships
            RETURN nodes, relationships
        """, rid=road_id, hops=hops)

        record = result.single()
        if not record:
            return {"error": "Road not found"}

        nodes = [dict(n) for n in record["nodes"]]
        rels = [dict(r) for r in record["relationships"]]

        return {
            "road": road_id,
            "hops": hops,
            "affected_nodes": nodes,
            "affected_edges": rels
        }
    
@app.get("/api/impact/semantic/{road_id}", response_model=ImpactSubgraphResponse)
def semantic_impact(road_id: int, hops: int = 3):
    with driver.session(database="neo4j") as neo:
        query = """
        MATCH (r:Road {osm_id: $road})
        CALL apoc.path.spanningTree(r, {
        relationshipFilter: "<CONNECTS_TO|CONNECTS_TO",
        minLevel: 0,
        maxLevel: $maxHops,
        bfs: true
        })
        YIELD path
        WITH last(nodes(path)) AS node, length(path) AS hop
        RETURN node, hop
"""




        records = neo.run(query, road=road_id, maxHops=hops)

        pg = get_pg_conn()
        pgcur = pg.cursor()

        result = []

        for record in records:
            node = record["node"]
            hop = record["hop"]

            if "Road" in node.labels:
                pgcur.execute(
                    "SELECT ST_AsGeoJSON(way) FROM planet_osm_roads WHERE osm_id=%s",
                    (int(node["osm_id"]),)
                )
                geom = pgcur.fetchone()
                coords = json.loads(geom[0])["coordinates"] if geom else None

                result.append(GraphEntity(
                    id=str(node["osm_id"]),
                    type="Road",
                    hop=hop,
                    geometry=coords
                ))

            elif "Hospital" in node.labels:
                pgcur.execute(
                    "SELECT ST_X(geom), ST_Y(geom) FROM hospitals WHERE id=%s",
                    (node["id"],)
                )
                pt = pgcur.fetchone()

                result.append(GraphEntity(
                    id=str(node["id"]),
                    type="Hospital",
                    hop=hop,
                    location=[pt[1], pt[0]] if pt else None
                ))

            elif "Zone" in node.labels:
                pgcur.execute(
                    "SELECT ST_AsGeoJSON(geom) FROM zones WHERE id=%s",
                    (node["id"],)
                )
                poly = pgcur.fetchone()
                poly_coords = json.loads(poly[0])["coordinates"] if poly else None

                result.append(GraphEntity(
                    id=str(node["id"]),
                    type="Zone",
                    hop=hop,
                    geometry=poly_coords
                ))

        pgcur.close()
        pg.close()

        return ImpactSubgraphResponse(
            root=str(road_id),
            max_hops=hops,
            subgraph=result
        )
    
@app.get("/api/impact/zones/{road_id}")
def zone_impact(road_id: int, hops: int = 3):
    with driver.session(database="neo4j") as neo:
        records = list(neo.run("""
        MATCH (root:Road {osm_id: $road})
        CALL apoc.path.spanningTree(
          root,
          {
            relationshipFilter: "CONNECTS_TO",
            minLevel: 0,
            maxLevel: $hops,
            bfs: true
          }
        )
        YIELD path
        WITH last(nodes(path)) AS r
        MATCH (r)-[:LOCATED_IN]->(z:Zone)
        WITH z, count(DISTINCT r) AS affected_roads

        MATCH (z)<-[:LOCATED_IN]-(all:Road)
        WITH
          z.zone_id AS zone_id,
          z.name AS zone_name,
          affected_roads,
          count(DISTINCT all) AS total_roads

        RETURN
          zone_id,
          zone_name,
          affected_roads,
          total_roads,
          round(toFloat(affected_roads) / total_roads, 3) AS severity
        ORDER BY severity DESC
        """, road=road_id, hops=hops))

    pg = psycopg2.connect(
        host=PG_HOST,
        port=PG_PORT,
        database=PG_DB,
        user=PG_USER,
        password=PG_PASS
    )
    cur = pg.cursor()

    zones = []

    for r in records:
        cur.execute("""
            SELECT ST_AsGeoJSON(way)
            FROM planet_osm_polygon
            WHERE name = %s
              AND boundary = 'administrative'
            LIMIT 1
        """, (r["zone_name"],))

        geom = cur.fetchone()
        if not geom:
            continue

        zones.append({
            "zone_id": r["zone_id"],
            "zone_name": r["zone_name"],
            "affected_roads": r["affected_roads"],
            "total_roads": r["total_roads"],
            "severity": float(r["severity"]),
            "geometry": json.loads(geom[0])["coordinates"]
        })

    cur.close()
    pg.close()

    return {
        "road_id": road_id,
        "hops": hops,
        "zones": zones
    }


@app.get("/api/impact/hospitals/{road_id}")
def hospital_impact(road_id: int, hops: int = 3):
    # 1️⃣ Neo4j BFS
    with driver.session(database="neo4j") as neo:
        records = neo.run("""
        MATCH (root:Road {osm_id: $road})
        CALL apoc.path.spanningTree(
          root,
          {
            relationshipFilter: "CONNECTS_TO",
            minLevel: 0,
            maxLevel: $hops,
            bfs: true
          }
        )
        YIELD path
        WITH last(nodes(path)) AS r, length(path) AS hop
        RETURN r.osm_id AS road_id, hop
        """, road=road_id, hops=hops)

        affected_roads = {
            r["road_id"]: r["hop"]
            for r in records
        }

    # 2️⃣ PostGIS hospital → nearest road
    pg = psycopg2.connect(
        host=PG_HOST,
        port=PG_PORT,
        database=PG_DB,
        user=PG_USER,
        password=PG_PASS
    )
    cur = pg.cursor()

    cur.execute("""
        SELECT
          h.osm_id,
          h.name,
          ST_Y(h.way) AS lat,
          ST_X(h.way) AS lon,
          r.osm_id AS road_id
        FROM planet_osm_point h
        JOIN LATERAL (
          SELECT osm_id
          FROM planet_osm_roads
          ORDER BY h.way <-> planet_osm_roads.way
          LIMIT 1
        ) r ON true
        WHERE h.amenity = 'hospital'
    """)

    hospitals = []

    for hid, name, lat, lon, road in cur.fetchall():
        if road in affected_roads:
            hop = affected_roads[road]

            if hop == 0:
                risk = "CRITICAL"
                reason = "Hospital is directly connected to the failed road. Immediate access disruption expected."
            elif hop == 1:
                risk = "HIGH"
                reason = "Hospital access roads are directly connected to the failed road."
            elif hop == 2:
                risk = "MEDIUM"
                reason = "Hospital is reachable only via secondary roads affected by the failure."
            else:
                risk = "LOW"
                reason = "Hospital is indirectly affected with alternative routes still available."

            # Find alternative safe road
            cur.execute("""
                SELECT osm_id
                FROM planet_osm_roads
                WHERE osm_id NOT IN %s
                ORDER BY way <-> ST_SetSRID(ST_Point(%s, %s), 4326)
                LIMIT 1
            """, (
                tuple(affected_roads.keys()),
                lon,
                lat
            ))
            alt = cur.fetchone()

            if alt:
                alt_road = alt[0]
                reroute = {
                    "suggested_road_id": alt_road,
                    "reason": "Nearest unaffected road providing alternative access"
                }
            else:
                reroute = None

            hospitals.append({
                "hospital_id": hid,
                "name": name,
                "location": [lat, lon],
                "hop": hop,
                "risk": risk,
                "reason": reason,
                "reroute": reroute
            })

    cur.close()
    pg.close()

    hospitals.sort(key=lambda x: x["hop"])

    return {
        "road_id": road_id,
        "hops": hops,
        "affected_hospitals": hospitals
    }

@app.get("/api/impact/summary/{road_id}")
def impact_summary(road_id: int, hops: int = 3):
    # reuse hospital logic
    with driver.session(database="neo4j") as neo:
        records = neo.run("""
        MATCH (root:Road {osm_id: $road})
        CALL apoc.path.spanningTree(
          root,
          {
            relationshipFilter: "CONNECTS_TO",
            minLevel: 0,
            maxLevel: $hops,
            bfs: true
          }
        )
        YIELD path
        WITH last(nodes(path)) AS r, length(path) AS hop
        RETURN r.osm_id AS road_id, hop
        """, road=road_id, hops=hops)

        affected_roads = {r["road_id"]: r["hop"] for r in records}

    pg = psycopg2.connect(
        host=PG_HOST,
        port=PG_PORT,
        database=PG_DB,
        user=PG_USER,
        password=PG_PASS
    )
    cur = pg.cursor()

    cur.execute("""
        SELECT
          h.osm_id,
          h.name,
          r.osm_id AS road_id
        FROM planet_osm_point h
        JOIN LATERAL (
          SELECT osm_id
          FROM planet_osm_roads
          ORDER BY h.way <-> planet_osm_roads.way
          LIMIT 1
        ) r ON true
        WHERE h.amenity = 'hospital'
    """)

    hospitals = []

    for hid, name, road in cur.fetchall():
        if road in affected_roads:
            hop = affected_roads[road]
            score = max(0, (hops + 1) - hop)  # higher = more critical

            if hop == 0:
                explanation = "Directly dependent on the failed road"
            elif hop == 1:
                explanation = "Dependent on immediate connecting roads"
            else:
                explanation = "Indirect dependency via secondary routes"

            hospitals.append({
                "name": name,
                "hop": hop,
                "priority_score": score,
                "explanation": explanation
            })

    cur.close()
    pg.close()

    hospitals.sort(key=lambda x: (-x["priority_score"], x["hop"]))

    return {
        "road_id": road_id,
        "top_hospitals": hospitals[:5]
    }

@app.post("/rag/ingest")
def ingest_documents():
    return ingest_pdfs("docs")

@app.post("/rag/query", response_model=RagAnswer)
def query_documents(question: str):
    return rag_query(question)



if __name__ == "__main__":
    print("Rebuilding road connectivity from PostGIS...")
    build_road_zone_links()
    build_road_connectivity_from_postgis()
    print("Done.")
