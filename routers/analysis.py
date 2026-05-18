from fastapi import APIRouter, HTTPException
from models.schemas import AnalyzeDraftRequest, LlmAssistRequest, AutoReplyRequest, LearyAnalysisRequest
from services.analysis import analyze_draft, analyze_leary
from services.gpt import call_llm_assist, call_auto_reply

router = APIRouter()


@router.post("/analyze-draft")
def route_analyze_draft(req: AnalyzeDraftRequest):
    return analyze_draft(req)


@router.post("/llm-assist")
def route_llm_assist(req: LlmAssistRequest):
    return call_llm_assist(req)


@router.post("/auto-reply")
def route_auto_reply(req: AutoReplyRequest):
    if not req.partnerLastMessage.strip():
        raise HTTPException(status_code=400, detail="상대방 마지막 메시지가 없어 자동 응답을 생성할 수 없습니다.")
    return call_auto_reply(req)


@router.post("/analyze-leary")
def route_analyze_leary(req: LearyAnalysisRequest):
    return analyze_leary(req.messages)
