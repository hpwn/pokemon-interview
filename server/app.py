from fastapi import FastAPI
from pydantic import BaseModel
from typing import List, Optional
import json
from pathlib import Path
from datetime import datetime

PROMPTS = {p["id"]: p for p in json.loads(Path(__file__).with_name("prompts.json").read_text())}

app = FastAPI()

class AIRequest(BaseModel):
    prompt_id: str
    topic: Optional[str] = None
    history: Optional[List[str]] = None
    answer: Optional[str] = None
    attempt: Optional[int] = 1

class AIResponse(BaseModel):
    text: str
    passed: bool
    hint: Optional[str] = None
    next_state: Optional[str] = None

def grade(prompt, user_answer: Optional[str]) -> tuple[bool, Optional[str]]:
    if not user_answer:
        return False, prompt["hints"][0] if prompt.get("hints") else None
    ans = user_answer.lower()
    keys = prompt.get("keywords", [])
    ok = any(k.lower() in ans for k in keys)
    return ok, None if ok else (prompt["hints"][0] if prompt.get("hints") else None)

@app.post("/ai", response_model=AIResponse)
def ai(req: AIRequest):
    prompt = PROMPTS.get(req.prompt_id) or next(iter(PROMPTS.values()))
    passed, hint = grade(prompt, req.answer)
    text = prompt["question"] if (req.attempt == 1 and not req.answer) else \
           ("✅ Correct! Nice work." if passed else "Not quite. Think about constant-time membership checks.")
    # simple log
    log_dir = Path.home() / "pokemon-career" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    (log_dir / f"{datetime.now():%Y-%m-%d}.md").write_text(
        f"{datetime.now():%H:%M:%S} | {req.prompt_id} | attempt={req.attempt} | passed={passed} | ans={req.answer}\n",
        append=True
    ) if hasattr(Path, "write_text") else None

    return AIResponse(text=text, passed=passed, hint=hint, next_state="done" if passed else "retry")
