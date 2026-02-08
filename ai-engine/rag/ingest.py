import os
from langchain_community.document_loaders import PyPDFLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from qdrant_client import QdrantClient
from qdrant_client.models import PointStruct, VectorParams, Distance
from rag.embeddings import embed_texts

QDRANT_COLLECTION = "city_docs"

def ingest_pdfs(pdf_dir="docs"):
    client = QdrantClient(path="/data/vector")

    splitter = RecursiveCharacterTextSplitter(
        chunk_size=800,
        chunk_overlap=150
    )

    points = []
    point_id = 0

    for file in os.listdir(pdf_dir):
        if not file.lower().endswith(".pdf"):
            continue

        loader = PyPDFLoader(os.path.join(pdf_dir, file))
        docs = loader.load()

        chunks = splitter.split_documents(docs)
        if not chunks:
            continue

        texts = [c.page_content for c in chunks]
        vectors = embed_texts(texts)

        for chunk, vector in zip(chunks, vectors):
            points.append(
                PointStruct(
                    id=point_id,
                    vector=vector.tolist(),
                    payload={
                        "document": file,
                        "page": chunk.metadata.get("page", -1),
                        "text": chunk.page_content
                    }
                )
            )
            point_id += 1

    if not points:
        return {"documents": 0, "chunks": 0}

    # ✅ correct attribute access
    vector_size = len(points[0].vector)

    client.recreate_collection(
        collection_name=QDRANT_COLLECTION,
        vectors_config=VectorParams(
            size=vector_size,
            distance=Distance.COSINE
        )
    )

    client.upsert(
        collection_name=QDRANT_COLLECTION,
        points=points
    )

    return {
        "documents": len(set(p.payload["document"] for p in points)),
        "chunks": len(points)
    }
