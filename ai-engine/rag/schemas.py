from pydantic import BaseModel
from typing import List, Dict, Any

class Citation(BaseModel):
    document: str
    page: int
    snippet: str

class RagAnswer(BaseModel):
    question: str
    answer: str
    citations: List[Citation]
    graph_entities: Dict[str, Any] = {}
    spatial_relations: List[Dict[str, Any]] = []
