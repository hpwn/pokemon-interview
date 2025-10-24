from fastapi import FastAPI
from pydantic import BaseModel
from typing import List, Optional, Literal, Dict, Any
from pathlib import Path
from datetime import datetime
import json

PromptType = Literal["mcq","tf","short","code"]

class AIRequest(BaseModel):
    prompt_id: Optional[str] = None
    topic: Optional[str] = None
    history: Optional[List[str]] = None
    attempt: Optional[int] = 1
    # unified answer fields (only one typically used per type)
    answer_text: Optional[str] = None      # for short/code
    answer_idx: Optional[int] = None       # for mcq
    answer_bool: Optional[bool] = None     # for tf

class AIResponse(BaseModel):
    text: str
    passed: bool
    hint: Optional[str] = None
    next_state: Optional[str] = None
    # optional: echo of choices for mcq
    choices: Optional[List[str]] = None

DATA = json.loads(Path(__file__).with_name("prompts.json").read_text(encoding="utf-8"))
PROMPTS: Dict[str, Dict[str, Any]] = {p["id"]: p for p in DATA}
ORDER = [p["id"] for p in DATA]

app = FastAPI()


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}

def append_log(line: str) -> None:
    log_dir = Path.home() / "pokemon-career" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    (log_dir / f"{datetime.now():%Y-%m-%d}.md").open("a", encoding="utf-8").write(line + "\n")

def pick_prompt(req: AIRequest) -> Dict[str, Any]:
    if req.prompt_id and req.prompt_id in PROMPTS:
        return PROMPTS[req.prompt_id]
    return PROMPTS[ORDER[0]]

def grade_mcq(p: Dict[str,Any], idx: Optional[int]) -> bool:
    return idx is not None and "answer_idx" in p and idx == int(p["answer_idx"])

def grade_tf(p: Dict[str,Any], val: Optional[bool]) -> bool:
    return val is not None and "answer_bool" in p and bool(val) == bool(p["answer_bool"])

def grade_keywords(p: Dict[str,Any], text: Optional[str]) -> bool:
    if not text: return False
    keys = [k.lower() for k in p.get("keywords",[])]
    ans  = text.lower()
    return any(k in ans for k in keys) if keys else False

@app.post("/ai", response_model=AIResponse)
def ai(req: AIRequest):
    p = pick_prompt(req)
    ptype: PromptType = p.get("type","short")  # default short

    # first contact: return question + choices (if any)
    if req.attempt == 1 and not (req.answer_text or req.answer_idx is not None or req.answer_bool is not None):
        resp = AIResponse(
            text=p["question"],
            passed=False,
            hint=(p.get("hints") or [None])[0],
            next_state="ask",
            choices=p.get("choices")
        )
        append_log(f"{datetime.now():%H:%M:%S} | {p['id']} | attempt={req.attempt} | ask")
        return resp

    # grade
    passed = False
    if ptype == "mcq":
        passed = grade_mcq(p, req.answer_idx)
    elif ptype == "tf":
        passed = grade_tf(p, req.answer_bool)
    elif ptype in ("short","code"):
        passed = grade_keywords(p, req.answer_text)

    hint = None if passed else (p.get("hints") or [None])[0]
    text = "✅ Correct!" if passed else "Not quite—try the hint."

    append_log(f"{datetime.now():%H:%M:%S} | {p['id']} | attempt={req.attempt} | passed={passed} | ans_idx={req.answer_idx} | ans_bool={req.answer_bool} | ans_text={(req.answer_text or '')[:60]}")

    return AIResponse(
        text=text,
        passed=passed,
        hint=hint,
        next_state="done" if passed else "retry",
        choices=p.get("choices") if ptype == "mcq" else None
    )
