from rag.entity_extractor import extract_entities
from rag.query_expander import expand_query
from rag.retriever import retrieve_chunks
from graph.entity_resolver import resolve_entities
from spatial.spatial_analyzer import analyze_road_hospital_proximity
from rag.schemas import RagAnswer, Citation
from google import genai
import os

def rag_query(question: str) -> RagAnswer:
    # 1️⃣ Entity extraction
    entities = extract_entities(question)

    # 2️⃣ Neo4j grounding
    graph_entities = resolve_entities(entities)

    # 3️⃣ Spatial grounding (PostGIS)
    spatial_relations = analyze_road_hospital_proximity(max_distance_m=200)

    # 2️⃣ Expand question
    expanded_queries = expand_query(question, entities)

    # 3️⃣ Retrieve relevant chunks
    hits = retrieve_chunks(expanded_queries)

    if not hits:
        return RagAnswer(
            question=question,
            answer="Not found in provided documents.",
            citations=[]
        )

    # 4️⃣ Build context
    context = "\n\n".join(
        f"[{h.payload['document']} | page {h.payload['page']}]\n{h.payload['text']}"
        for h in hits
    )

    prompt = f"""
You are a city planning regulation expert.

Use the context below to answer the question.
You may combine information across sections.
Do NOT invent rules.

Context:
{context}

Question:
{question}
"""

    client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))

    response = client.models.generate_content(
        model="gemini-2.5-flash",
        contents=prompt
    )

    answer = response.text or "Not found in provided documents."

    citations = [
        Citation(
            document=h.payload["document"],
            page=h.payload["page"],
            snippet=h.payload["text"][:200]
        )
        for h in hits
    ]

    return RagAnswer(
        question=question,
        answer=answer,
        citations=citations,
        graph_entities=graph_entities,
        spatial_relations=spatial_relations
    )
