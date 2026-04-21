"""Initialize backend database tables."""

from __future__ import annotations

import json

from backend.app.core.config import get_settings
from backend.app.core.db import get_database_status, init_database


def main() -> None:
    settings = get_settings()
    init_result = init_database(settings.database_url)
    status = get_database_status(settings.database_url)
    print(
        json.dumps(
            {
                "database": status.get("database"),
                "connected": status.get("connected"),
                "created_tables": init_result["created_tables"],
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
