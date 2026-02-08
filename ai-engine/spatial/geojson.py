def to_feature_collection(geoms, properties=None):
    features = []

    for g in geoms:
        features.append({
            "type": "Feature",
            "geometry": g["geometry"],
            "properties": properties or {}
        })

    return {
        "type": "FeatureCollection",
        "features": features
    }
