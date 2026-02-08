def expand_query(question: str, entities: dict) -> list[str]:
    """
    Convert natural question into regulation-style search queries.
    """

    expanded = [question]

    if "building_type" in entities:
        for b in entities["building_type"]:
            expanded.extend([
                f"{b} buffer zone regulations",
                f"{b} land use restrictions",
                f"{b} institutional building norms",
                f"{b} silence zone rules"
            ])

    if "infrastructure" in entities:
        for i in entities["infrastructure"]:
            expanded.extend([
                f"{i} construction regulations",
                f"{i} development control rules",
                f"{i} right of way norms"
            ])

    return list(set(expanded))
