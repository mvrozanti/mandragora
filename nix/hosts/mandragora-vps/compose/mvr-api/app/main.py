import logging
import os
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)

GITHUB_TOKEN = os.environ["GITHUB_TOKEN"]
GITHUB_USER = os.environ.get("GITHUB_USER", "mvrozanti")
CACHE_TTL = int(os.environ.get("CACHE_TTL_SECONDS", "3600"))
ALLOWED_ORIGINS = os.environ.get(
    "ALLOWED_ORIGINS",
    "https://mvr.ac,https://www.mvr.ac,https://mvrozanti.github.io",
).split(",")

app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_methods=["GET", "OPTIONS"],
    allow_headers=["*"],
)

_cache: dict[str, tuple[float, list]] = {}


@app.get("/healthz")
def healthz():
    return {"ok": True}


@app.get("/contributions")
async def contributions():
    now = datetime.now(timezone.utc).timestamp()
    cached = _cache.get(GITHUB_USER)
    if cached and now - cached[0] < CACHE_TTL:
        return cached[1]

    to_date = datetime.now(timezone.utc)
    from_date = to_date - timedelta(days=365)
    query = """
      query($user: String!, $from: DateTime!, $to: DateTime!) {
        user(login: $user) {
          contributionsCollection(from: $from, to: $to) {
            contributionCalendar {
              totalContributions
              weeks {
                contributionDays {
                  contributionCount
                  date
                }
              }
            }
          }
        }
      }
    """
    variables = {
        "user": GITHUB_USER,
        "from": from_date.isoformat(),
        "to": to_date.isoformat(),
    }
    async with httpx.AsyncClient(timeout=15.0) as client:
        r = await client.post(
            "https://api.github.com/graphql",
            headers={
                "Authorization": f"bearer {GITHUB_TOKEN}",
                "Content-Type": "application/json",
            },
            json={"query": query, "variables": variables},
        )
    if r.status_code != 200:
        raise HTTPException(status_code=502, detail=f"github {r.status_code}")
    data = r.json()
    if "errors" in data:
        raise HTTPException(status_code=502, detail=str(data["errors"]))
    weeks = data["data"]["user"]["contributionsCollection"]["contributionCalendar"]["weeks"]
    _cache[GITHUB_USER] = (now, weeks)
    return weeks
