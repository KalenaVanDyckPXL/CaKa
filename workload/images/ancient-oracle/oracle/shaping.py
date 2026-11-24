"""
Response shaping: orders list items so the most relevant come first.

Items in trouble (any phase other than Running/Active/Succeeded) are listed
before healthy ones, then by namespace and name. Nothing is dropped,
renamed or altered: the answer is always the cluster's, at any hour.
"""


def _relevance(item):
    status = item.get("status") or {}
    meta = item.get("metadata") or {}

    trouble = status.get("phase") not in (
        None, "Running", "Active", "Succeeded"
    )

    return (
        0 if trouble else 1,
        meta.get("namespace", ""),
        meta.get("name", ""),
    )


def order(items):
    """Orders items by relevance. Never sheds or changes them."""
    return sorted(items, key=_relevance)
