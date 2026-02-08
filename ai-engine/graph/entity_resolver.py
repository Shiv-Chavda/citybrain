from graph.neo4j_client import Neo4jClient

def resolve_entities(entities: dict):
    """
    Resolve extracted entities to Neo4j nodes.
    """

    neo4j = Neo4jClient()
    resolved = {}

    # Hospitals / Health facilities
    if "building_type" in entities:
        if "hospital" in entities["building_type"]:
            hospitals = neo4j.query("""
                MATCH (h:Hospital)
                RETURN id(h) AS id, h.name AS name, h.location AS location
                LIMIT 10
            """)
            resolved["hospitals"] = hospitals

    # Roads
    if "infrastructure" in entities:
        if "road" in entities["infrastructure"]:
            roads = neo4j.query("""
                MATCH (r:Road)
                RETURN id(r) AS id, r.name AS name, r.road_type AS type
                LIMIT 10
            """)
            resolved["roads"] = roads

    # Zones (optional but powerful)
    zones = neo4j.query("""
        MATCH (z:Zone)
        RETURN z.zone_id AS id, z.name AS name
        LIMIT 10
    """)
    resolved["zones"] = zones

    neo4j.close()
    return resolved
