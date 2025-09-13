# backend/app/schemas.py
from pydantic import BaseModel
from typing import List

class UploadSummary(BaseModel):
    rows: int
    columns: List[str]
    inferred_timeframe: str | None
