from typing import List, Optional
from pydantic import BaseModel


class LoginRequest(BaseModel):
    username: str
    password: str


class SignupRequest(BaseModel):
    user_id: str
    password: str
    nickname: str
    status_message: Optional[str] = None


class UpdateNicknameRequest(BaseModel):
    user_id: str
    nickname: str


class UpdateStatusRequest(BaseModel):
    user_id: str
    status_message: str


class FriendRequest(BaseModel):
    user_id: str
    friend_id: str


class DirectRoomRequest(BaseModel):
    user_id: str
    friend_id: str


class AssistMessage(BaseModel):
    role: str
    text: str


class LlmAssistRequest(BaseModel):
    recentMessages: List[AssistMessage]
    partnerLastMessage: str
    draft: str
    llmCandidatePayload: Optional[dict] = None


class AutoReplyRequest(BaseModel):
    recentMessages: List[AssistMessage]
    partnerLastMessage: str


class AnalyzeDraftRequest(BaseModel):
    recentMessages: List[AssistMessage]
    partnerLastMessage: str
    draft: str


class LearyAnalysisRequest(BaseModel):
    messages: List[AssistMessage]
