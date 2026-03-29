"""
JSON serialization helpers with optional orjson acceleration.

If ``orjson`` is installed, it is used for both serialization and
deserialization (typically 3–10× faster than the stdlib ``json``
module). Otherwise, falls back transparently to ``json``.

This module is internal — import from ``msdrg`` instead.
"""

from __future__ import annotations

from typing import Any

try:
    import orjson

    def dumps(obj: Any) -> bytes:
        """Serialize *obj* to UTF-8 bytes."""
        return orjson.dumps(obj)

    def loads(data: str | bytes) -> Any:
        """Deserialize a JSON string or bytes to a Python object."""
        return orjson.loads(data)

except ImportError:
    import json

    def dumps(obj: Any) -> bytes:  # type: ignore[misc]
        """Serialize *obj* to UTF-8 bytes."""
        return json.dumps(obj).encode("utf-8")

    def loads(data: str | bytes) -> Any:  # type: ignore[misc]
        """Deserialize a JSON string or bytes to a Python object."""
        return json.loads(data)
