from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    project_id: str
    admin_static_dir: Path
    allowed_origins: tuple[str, ...]

    @classmethod
    def from_environment(cls) -> "Settings":
        workspace = Path(__file__).resolve().parents[2]
        origins = tuple(
            origin.strip()
            for origin in os.getenv("ALLOWED_ORIGINS", "").split(",")
            if origin.strip()
        )
        return cls(
            project_id=os.getenv("FIREBASE_PROJECT_ID", "backcourt-41720"),
            admin_static_dir=Path(
                os.getenv(
                    "ADMIN_STATIC_DIR",
                    str(workspace / "Backcourt-Admin"),
                )
            ),
            allowed_origins=origins,
        )


settings = Settings.from_environment()
