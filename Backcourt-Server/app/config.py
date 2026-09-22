from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    project_id: str
    admin_static_dir: Path
    site_static_dir: Path
    allowed_origins: tuple[str, ...]
    cloudinary_cloud_name: str
    cloudinary_api_key: str
    cloudinary_api_secret: str

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
            site_static_dir=Path(
                os.getenv(
                    "SITE_STATIC_DIR",
                    str(workspace / "Backcourt-Web"),
                )
            ),
            allowed_origins=origins,
            cloudinary_cloud_name=os.getenv("CLOUDINARY_CLOUD_NAME", "djrcsqpux"),
            cloudinary_api_key=os.getenv("CLOUDINARY_API_KEY", ""),
            cloudinary_api_secret=os.getenv("CLOUDINARY_API_SECRET", ""),
        )


settings = Settings.from_environment()
