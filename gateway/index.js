const express = require("express");
const cors = require("cors");
const { Pool } = require("pg");

const app = express();
app.use(cors());
app.use(express.json());

const pool = new Pool({
  host: "localhost",
  port: 5433,
  user: "citybrain",
  password: "citybrain",
  database: "citybrain",
});

// Health check
app.get("/health", (req, res) => {
  res.json({ status: "CityBrain Gateway Running" });
});

// Get roads (GeoJSON)
app.get("/api/roads", async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT jsonb_build_object(
        'type', 'FeatureCollection',
        'features', jsonb_agg(ST_AsGeoJSON(t.*)::jsonb)
      )
      FROM (
        SELECT osm_id, name, highway, way
        FROM planet_osm_roads
        WHERE highway IS NOT NULL
        LIMIT 2000
      ) t;
    `);
    res.json(result.rows[0].jsonb_build_object);
  } catch (err) {
    console.error(err);
    res.status(500).send("Error fetching roads");
  }
});

app.get("/api/impact/zones/:roadId", async (req, res) => {
  const { roadId } = req.params;
  const hops = req.query.hops || 3;

  try {
    const response = await fetch(
      `http://localhost:8001/api/impact/zones/${roadId}?hops=${hops}`
    );
    const data = await response.json();
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: "Zone impact service unavailable" });
  }
});


app.get("/api/impact/:roadId", async (req, res) => {
  const roadId = req.params.roadId;
  const hops = req.query.hops || 2;

  try {
    const response = await fetch(`http://localhost:8001/impact/road/${roadId}?hops=${hops}`);
    const data = await response.json();
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: "Impact service unavailable" });
  }
});

app.get("/api/impact/hospitals/:roadId", async (req, res) => {
  const { roadId } = req.params;
  const hops = req.query.hops || 3;

  const r = await fetch(
    `http://localhost:8001/api/impact/hospitals/${roadId}?hops=${hops}`
  );
  res.json(await r.json());
});


app.get("/api/nearest-road", async (req, res) => {
  const { lat, lng } = req.query;

  const query = `
    SELECT osm_id
    FROM planet_osm_roads
    ORDER BY way <-> ST_SetSRID(ST_Point($1, $2), 4326)
    LIMIT 1;
  `;

  try {
    const result = await pool.query(query, [lng, lat]);
    res.json({ road_id: result.rows[0].osm_id });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});



const PORT = 4000;
app.listen(PORT, () => {
  console.log(`CityBrain Gateway running on http://localhost:${PORT}`);
});
