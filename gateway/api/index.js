import dotenv from "dotenv";
import express from "express";

dotenv.config();
import cors from "cors";
import Pool from "pg";

const app = express();
app.use(cors());
app.use(express.json());

const pool = new Pool({
  host: process.env.POSTGRES_HOST || "localhost",
  port: parseInt(process.env.POSTGRES_PORT) || 5433,
  user: process.env.POSTGRES_USER || "citybrain",
  password: process.env.POSTGRES_PASSWORD || "citybrain",
  database: process.env.POSTGRES_DB || "citybrain",
  ssl: { rejectUnauthorized: false }
});

// Health check
app.get("/api/health", (req, res) => {
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
      `https://citybrain.onrender.com/api/impact/zones/${roadId}?hops=${hops}`
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
    const response = await fetch(`https://citybrain.onrender.com/impact/road/${roadId}?hops=${hops}`);
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
    `https://citybrain.onrender.com/api/impact/hospitals/${roadId}?hops=${hops}`
  );
  res.json(await r.json());
});

app.get("/api/impact/summary/:roadId", async (req, res) => {
  const { roadId } = req.params;
  const hops = req.query.hops || 3;

  try {
    const response = await fetch(
      `https://citybrain.onrender.com/api/impact/summary/${roadId}?hops=${hops}`
    );
    const data = await response.json();
    res.json(data);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Impact summary service unavailable" });
  }
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

app.get("/api/impact/junction/:junctionId", async (req, res) => {
  const { junctionId } = req.params;

  try {
    const r = await fetch(
      `https://citybrain.onrender.com/api/impact/junction/${junctionId}`
    );
    res.json(await r.json());
  } catch (err) {
    res.status(500).json({ error: "Junction impact service unavailable" });
  }
});

app.get("/api/impact/construction/:roadId", async (req, res) => {
  const { roadId } = req.params;

  try {
    const r = await fetch(
      `https://citybrain.onrender.com/api/impact/construction/${roadId}`
    );
    res.json(await r.json());
  } catch (err) {
    res.status(500).json({ error: "Construction impact service unavailable" });
  }
});

app.get("/api/construction/geometry", async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT
        id,
        ST_AsGeoJSON(geom) AS geometry,
        risk_factor
      FROM construction_projects
    `);

    res.json(result.rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get("/api/junctions", async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT
        id,
        ST_Y(geom) AS lat,
        ST_X(geom) AS lon
      FROM road_junctions
      LIMIT 5000
    `);

    res.json(result.rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get("/api/map/hospital-buffers", async (req, res) => {
  try {
    const r = await fetch("https://citybrain.onrender.com/map/hospital-buffers");
    res.json(await r.json());
  } catch (e) {
    res.status(500).json({ error: "Hospital buffer service unavailable" });
  }
});

app.get("/api/violations/construction-hospitals", async (req, res) => {
  try {
    const r = await fetch(
      "https://citybrain.onrender.com/map/violations/construction-hospitals"
    );
    res.json(await r.json());
  } catch (e) {
    res.status(500).json({ error: "Violation detection service unavailable" });
  }
});



app.get("/api/hospitals/buffers", async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT jsonb_build_object(
        'type', 'FeatureCollection',
        'features', jsonb_agg(
          jsonb_build_object(
            'type', 'Feature',
            'geometry', ST_AsGeoJSON(geom)::jsonb,
            'properties', jsonb_build_object(
              'hospital_id', hospital_id,
              'radius_m', radius_m
            )
          )
        )
      )
      FROM hospital_buffers
    `);

    res.json(result.rows[0].jsonb_build_object);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});


// ---------------------------------------------------
// Hospital buffer zones (proxy to AI engine)
// ---------------------------------------------------
app.get("/api/map/buffer/hospitals", async (req, res) => {
  const distance = req.query.distance || 100;

  try {
    const r = await fetch(
      `https://citybrain.onrender.com/map/buffer/hospitals?distance=${distance}`
    );

    if (!r.ok) {
      throw new Error("AI engine error");
    }

    const data = await r.json();
    res.json(data);
  } catch (err) {
    console.error(err);
    res.status(500).json({
      error: "Hospital buffer service unavailable",
    });
  }
});

app.get("/api/map/highlight/:entity", async (req, res) => {
  const { entity } = req.params;

  try {
    const r = await fetch(
      `https://citybrain.onrender.com/map/highlight?entity=${entity}`
    );

    if (!r.ok) {
      return res.status(500).json({
        error: "FastAPI highlight error",
        status: r.status,
      });
    }

    const data = await r.json();
    res.json(data);
  } catch (err) {
    console.error(err);
    res.status(500).json({
      error: "Map highlight service unavailable",
    });
  }
});


app.get("/api/map/highlight/hospitals", async (req, res) => {
  try {
    const r = await fetch(
      "https://citybrain.onrender.com/map/highlight?entity=hospital"
    );
    const data = await r.json();
    res.json(data);
  } catch (err) {
    console.error(err);
    res.status(500).json({
      error: "Hospital highlight service unavailable"
    });
  }
});


app.post("/api/rag/query", async (req, res) => {
  const { question } = req.body;

  const r = await fetch("https://citybrain.onrender.com/rag/query", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ question })
  });

  res.json(await r.json());
});


app.get("/", (req, res) => {
  res.json({ message: "CityBrain Gateway running on Vercel 🚀" });
});

export default app;
