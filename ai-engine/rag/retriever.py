from qdrant_client import QdrantClient
from rag.embeddings import embed_texts

QDRANT_COLLECTION = "city_docs"

def retrieve_chunks(queries: list[str], limit=8):
    client = QdrantClient(path="/data/vector")

    all_hits = []

    for q in queries:
        vector = embed_texts([q])[0]

        hits = client.search(
            collection_name=QDRANT_COLLECTION,
            query_vector=vector.tolist(),
            limit=limit
        )

        all_hits.extend(hits)

    # Deduplicate by point id
    unique = {h.id: h for h in all_hits}

    return list(unique.values())
