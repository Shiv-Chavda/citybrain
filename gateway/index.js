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

const PORT = 4000;
app.listen(PORT, () => {
  console.log(`CityBrain Gateway running on http://localhost:${PORT}`);
});
