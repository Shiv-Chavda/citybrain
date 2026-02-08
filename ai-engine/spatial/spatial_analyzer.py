from spatial.postgis_client import PostGISClient

def analyze_road_hospital_proximity(max_distance_m=200):
    db = PostGISClient()
    sql = """
    SELECT
        h.osm_id      AS hospital_id,
        h.name        AS hospital_name,
        r.osm_id      AS road_id,
        r.name        AS road_name,
        ST_Distance(
            ST_Transform(h.way, 3857),
            ST_Transform(r.way, 3857)
        ) AS distance_m
    FROM planet_osm_point h
    JOIN planet_osm_roads r
      ON ST_DWithin(
           ST_Transform(h.way, 3857),
           ST_Transform(r.way, 3857),
           %s
         )
    WHERE h.amenity = 'hospital'
      AND r.highway IS NOT NULL
    ORDER BY distance_m ASC
    LIMIT 50;
    """
    return db.query(sql, [max_distance_m])

    db.close()

    return results
