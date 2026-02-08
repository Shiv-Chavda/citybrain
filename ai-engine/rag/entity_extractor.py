from google import genai
import os
import json

def extract_entities(question: str) -> dict:
    """
    Extract city-planning entities from user question.
    """

    client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))

    prompt = f"""
Extract planning-related entities from the question.

Return JSON only.

Possible entity types:
- land_use
- building_type
- infrastructure
- regulation_concept

Question:
{question}

Example output:
{{
  "building_type": ["hospital"],
  "infrastructure": ["road"],
  "regulation_concept": ["construction restriction"]
}}
"""

    response = client.models.generate_content(
        model="gemini-2.5-flash",
        contents=prompt
    )

    try:
        return json.loads(response.text)
    except Exception:
        return {}
