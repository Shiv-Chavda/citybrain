from neo4j import GraphDatabase
import os

class Neo4jClient:
    def __init__(self):
        self.driver = GraphDatabase.driver(
            os.getenv("NEO4J_URI", "bolt://neo4j:7687"),
            auth=(
                os.getenv("NEO4J_USER", "neo4j"),
                os.getenv("NEO4J_PASSWORD", "password")
            )
        )

    def close(self):
        self.driver.close()

    def query(self, cypher: str, params: dict = {}):
        with self.driver.session() as session:
            result = session.run(cypher, params)
            return [r.data() for r in result]
