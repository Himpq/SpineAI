# -*- coding: utf-8 -*-
import base64
import io
import json
import math
import os
import secrets
import threading
import uuid
from collections import defaultdict
from datetime import date, datetime, timedelta
from functools import wraps
from pathlib import Path

import qrcode
import requests
from flask import Flask, Response, abort, g, jsonify, make_response, render_template, request, session, url_for
from flask_sqlalchemy import SQLAlchemy
from flask_sock import Sock
from PIL import Image, ImageDraw
from sqlalchemy import and_, func, or_, text
from werkzeug.security import check_password_hash, generate_password_hash
from werkzeug.utils import secure_filename

BASE_DIR = Path(__file__).resolve().parent
UPLOAD_DIR = BASE_DIR / "static" / "uploads"
DB_PATH = BASE_DIR / "spine_workbench.db"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

app = Flask(__name__)
app.config.update(
    SECRET_KEY=os.getenv("FLASK_SECRET_KEY", "spine-workbench-secret-change-me"),
    SQLALCHEMY_DATABASE_URI=f"sqlite:///{DB_PATH.as_posix()}",
    SQLALCHEMY_TRACK_MODIFICATIONS=False,
    MAX_CONTENT_LENGTH=64 * 1024 * 1024,
    REMOTE_INFER_BASE=os.getenv("SPINE_REMOTE_INFER_BASE", os.getenv("SPINE_REMOTE_INFER_URL", "http://spine.healthit.cn:15443")),
    REMOTE_INFER_TIMEOUT=int(os.getenv("SPINE_REMOTE_TIMEOUT", "60")),
    ALERT_COBB=float(os.getenv("SPINE_ALERT_COBB", "45")),
    PERMANENT_SESSION_LIFETIME=timedelta(days=30),
    STEPFUN_API_BASE=os.getenv("STEPFUN_API_BASE", "https://api.stepfun.com/v1"),
    STEPFUN_API_KEY=os.getenv("STEPFUN_API_KEY", "4A8Sj05GX9sf5mM6eOjTaqGu41UIyriGmUCBRQMapW4YehPDX54ZXjvOGzt9D2mZe"),
    STEPFUN_MODEL=os.getenv("STEPFUN_MODEL", "step-1-8k"),
    ANON_INFER_LIMIT=int(os.getenv("SPINE_ANON_INFER_LIMIT", "3")),
    ANON_INFER_WINDOW=int(os.getenv("SPINE_ANON_INFER_WINDOW", "3600")),
)

db = SQLAlchemy(app)
sock = Sock(app)

from flask_cors import CORS
CORS(app, resources={
    r"/api/public/*": {"origins": "*"},
    r"/static/*": {"origins": "*"},
    r"/ws": {"origins": "*"},
    r"/healthz": {"origins": "*"},
})

ROLE_OPTIONS = {"admin", "doctor", "nurse"}
DEFAULT_MODULES = [
    "overview",
    "followup",
    "review",
    "chat",
    "questionnaire",
    "status",
    "users",
]
ALLOWED_UPLOAD_EXT = {".png", ".jpg", ".jpeg", ".bmp", ".webp"}

WS_LOCK = threading.Lock()
WS_CHANNELS = defaultdict(set)
WS_META = {}


def utcnow():
    return datetime.utcnow()


def json_dumps(value):
    return json.dumps(value, ensure_ascii=False)


def json_loads(raw, default=None):
    if raw is None:
        return default
    try:
        return json.loads(raw)
    except (TypeError, json.JSONDecodeError):
        return default


def iso(dt_value):
    if not dt_value:
        return None
    return dt_value.isoformat(timespec="seconds") + "Z"


def parse_iso(raw_value):
    if not raw_value:
        return None
    try:
        return datetime.fromisoformat(str(raw_value).replace("Z", "+00:00")).replace(tzinfo=None)
    except ValueError:
        return None


def to_float(value, default=None):
    try:
        if value is None:
            return default
        return float(value)
    except (TypeError, ValueError):
        return default


def to_bool(value, default=False):
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    text_value = str(value).strip().lower()
    if text_value in {"1", "true", "yes", "on", "y"}:
        return True
    if text_value in {"0", "false", "no", "off", "n"}:
        return False
    return default


def generate_token(prefix=""):
    token = secrets.token_urlsafe(18).replace("-", "").replace("_", "")
    return f"{prefix}{token}"


def api_ok(data=None, message="ok"):
    return jsonify({"ok": True, "message": message, "data": data or {}})


def api_error(message, status=400, code="bad_request", details=None):
    return (
        jsonify(
            {
                "ok": False,
                "error": {
                    "code": code,
                    "message": message,
                    "details": details,
                },
            }
        ),
        status,
    )


@app.errorhandler(404)
def handle_404(e):
    if request.path.startswith("/api/"):
        return api_error("请求的资源不存在", status=404, code="not_found")
    return e


@app.errorhandler(405)
def handle_405(e):
    if request.path.startswith("/api/"):
        return api_error("请求方法不支持", status=405, code="method_not_allowed")
    return e


def module_defaults_for_role(role):
    if role == "admin":
        return DEFAULT_MODULES
    if role == "doctor":
        return ["overview", "followup", "review", "chat", "questionnaire", "status"]
    return ["overview", "followup", "chat", "questionnaire", "status"]


class User(db.Model):
    __tablename__ = "wb_users"

    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(64), unique=True, nullable=False, index=True)
    display_name = db.Column(db.String(64), nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    role = db.Column(db.String(16), nullable=False, default="doctor")
    is_active = db.Column(db.Boolean, nullable=False, default=True)
    module_permissions = db.Column(db.Text, nullable=False, default="[]")
    last_login_at = db.Column(db.DateTime, nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=utcnow, onupdate=utcnow)

    def set_password(self, raw_password):
        self.password_hash = generate_password_hash(raw_password)

    def check_password(self, raw_password):
        return check_password_hash(self.password_hash, raw_password)

    def modules(self):
        modules = json_loads(self.module_permissions, []) or []
        if not isinstance(modules, list) or not modules:
            return module_defaults_for_role(self.role)
        valid = set(DEFAULT_MODULES)
        if not any(m in valid for m in modules):
            return module_defaults_for_role(self.role)
        return [m for m in modules if m in valid]

    def serialize(self):
        return {
            "id": self.id,
            "username": self.username,
            "display_name": self.display_name,
            "role": self.role,
            "is_active": self.is_active,
            "module_permissions": self.modules(),
            "last_login_at": iso(self.last_login_at),
            "created_at": iso(self.created_at),
        }


class Patient(db.Model):
    __tablename__ = "wb_patients"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(64), nullable=False)
    age = db.Column(db.Integer, nullable=True)
    sex = db.Column(db.String(16), nullable=True)
    phone = db.Column(db.String(32), nullable=True)
    email = db.Column(db.String(120), nullable=True)
    note = db.Column(db.Text, nullable=True)
    portal_token = db.Column(db.String(64), unique=True, nullable=False, index=True)
    created_by_user_id = db.Column(db.Integer, db.ForeignKey("wb_users.id"), nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=utcnow, onupdate=utcnow)


class RegistrationSession(db.Model):
    __tablename__ = "wb_registration_sessions"

    id = db.Column(db.Integer, primary_key=True)
    token = db.Column(db.String(64), unique=True, nullable=False, index=True)
    created_by_user_id = db.Column(db.Integer, db.ForeignKey("wb_users.id"), nullable=True)
    patient_id = db.Column(db.Integer, db.ForeignKey("wb_patients.id"), nullable=True)
    form_state = db.Column(db.Text, nullable=False, default="{}")
    focus_field = db.Column(db.String(64), nullable=True)
    status = db.Column(db.String(24), nullable=False, default="active")
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=utcnow, onupdate=utcnow)


class Exam(db.Model):
    __tablename__ = "wb_exams"

    id = db.Column(db.Integer, primary_key=True)
    patient_id = db.Column(db.Integer, db.ForeignKey("wb_patients.id"), nullable=False, index=True)
    image_path = db.Column(db.String(256), nullable=False)
    uploaded_by_kind = db.Column(db.String(16), nullable=False, default="doctor")
    uploaded_by_user_id = db.Column(db.Integer, db.ForeignKey("wb_users.id"), nullable=True)
    uploaded_by_label = db.Column(db.String(64), nullable=True)
    review_owner_user_id = db.Column(db.Integer, db.ForeignKey("wb_users.id"), nullable=True)
    status = db.Column(db.String(24), nullable=False, default="pending_review")
    inference_json = db.Column(db.Text, nullable=False, default="{}")
    inference_image_path = db.Column(db.String(256), nullable=True)
    spine_class = db.Column(db.String(24), nullable=True)
    spine_class_id = db.Column(db.Integer, nullable=True)
    spine_class_confidence = db.Column(db.Float, nullable=True)
    cobb_angle = db.Column(db.Float, nullable=True)
    curve_value = db.Column(db.Float, nullable=True)
    severity_label = db.Column(db.String(24), nullable=True)
    improvement_value = db.Column(db.Float, nullable=True)
    review_note = db.Column(db.Text, nullable=True)
    reviewed_by_user_id = db.Column(db.Integer, db.ForeignKey("wb_users.id"), nullable=True)
    reviewed_at = db.Column(db.DateTime, nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=utcnow, onupdate=utcnow)

    patient = db.relationship("Patient", backref=db.backref("exams", cascade="all, delete-orphan"))


class InferenceJob(db.Model):
    __tablename__ = "wb_inference_jobs"

    id = db.Column(db.Integer, primary_key=True)
    exam_id = db.Column(db.Integer, db.ForeignKey("wb_exams.id"), nullable=False, index=True)
    status = db.Column(db.String(16), nullable=False, default="queued")
    queued_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    started_at = db.Column(db.DateTime, nullable=True)
    finished_at = db.Column(db.DateTime, nullable=True)
    latency_ms = db.Column(db.Integer, nullable=True)
    error_message = db.Column(db.Text, nullable=True)


class FollowUpSchedule(db.Model):
    __tablename__ = "wb_schedules"

    id = db.Column(db.Integer, primary_key=True)
    patient_id = db.Column(db.Integer, db.ForeignKey("wb_patients.id"), nullable=False)
    title = db.Column(db.String(120), nullable=False)
    note = db.Column(db.Text, nullable=True)
    scheduled_at = db.Column(db.DateTime, nullable=False)
    status = db.Column(db.String(16), nullable=False, default="todo")
    created_by_user_id = db.Column(db.Integer, db.ForeignKey("wb_users.id"), nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=utcnow, onupdate=utcnow)

    patient = db.relationship("Patient", backref=db.backref("schedules", cascade="all, delete-orphan"))


class WorkEvent(db.Model):
    __tablename__ = "wb_work_events"

    id = db.Column(db.Integer, primary_key=True)
    event_type = db.Column(db.String(32), nullable=False)
    title = db.Column(db.String(160), nullable=False)
    message = db.Column(db.Text, nullable=False)
    level = db.Column(db.String(16), nullable=False, default="info")
    patient_id = db.Column(db.Integer, db.ForeignKey("wb_patients.id"), nullable=True)
    exam_id = db.Column(db.Integer, db.ForeignKey("wb_exams.id"), nullable=True)
    ref_json = db.Column(db.Text, nullable=False, default="{}")
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)


class Conversation(db.Model):
    __tablename__ = "wb_conversations"

    id = db.Column(db.Integer, primary_key=True)
    type = db.Column(db.String(16), nullable=False, default="private")
    name = db.Column(db.String(120), nullable=True)
    patient_id = db.Column(db.Integer, db.ForeignKey("wb_patients.id"), nullable=True)
    created_by_user_id = db.Column(db.Integer, db.ForeignKey("wb_users.id"), nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=utcnow)


class ConversationParticipant(db.Model):
    __tablename__ = "wb_conversation_participants"
    __table_args__ = (db.UniqueConstraint("conversation_id", "user_id", name="uq_wb_conv_user"),)

    id = db.Column(db.Integer, primary_key=True)
    conversation_id = db.Column(db.Integer, db.ForeignKey("wb_conversations.id"), nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey("wb_users.id"), nullable=False)
    joined_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    last_read_message_id = db.Column(db.Integer, nullable=True)


class Message(db.Model):
    __tablename__ = "wb_messages"

    id = db.Column(db.Integer, primary_key=True)
    conversation_id = db.Column(db.Integer, db.ForeignKey("wb_conversations.id"), nullable=False, index=True)
    sender_kind = db.Column(db.String(16), nullable=False, default="user")
    sender_user_id = db.Column(db.Integer, db.ForeignKey("wb_users.id"), nullable=True)
    sender_name = db.Column(db.String(64), nullable=False)
    message_type = db.Column(db.String(24), nullable=False, default="text")
    content = db.Column(db.Text, nullable=False)
    payload_json = db.Column(db.Text, nullable=False, default="{}")
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)

class ExamShareLink(db.Model):
    __tablename__ = "wb_exam_share_links"

    id = db.Column(db.Integer, primary_key=True)
    exam_id = db.Column(db.Integer, db.ForeignKey("wb_exams.id"), nullable=False, unique=True)
    token = db.Column(db.String(64), nullable=False, unique=True, index=True)
    created_by_user_id = db.Column(db.Integer, db.ForeignKey("wb_users.id"), nullable=True)
    is_active = db.Column(db.Boolean, nullable=False, default=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)


class ShareAccessLog(db.Model):
    __tablename__ = "wb_share_access_logs"

    id = db.Column(db.Integer, primary_key=True)
    share_link_id = db.Column(db.Integer, db.ForeignKey("wb_exam_share_links.id"), nullable=False)
    access_ip = db.Column(db.String(64), nullable=True)
    user_agent = db.Column(db.Text, nullable=True)
    viewer_label = db.Column(db.String(80), nullable=True)
    accessed_at = db.Column(db.DateTime, nullable=False, default=utcnow)


class ExamComment(db.Model):
    __tablename__ = "wb_exam_comments"

    id = db.Column(db.Integer, primary_key=True)
    exam_id = db.Column(db.Integer, db.ForeignKey("wb_exams.id"), nullable=False, index=True)
    author_kind = db.Column(db.String(16), nullable=False, default="user")
    author_user_id = db.Column(db.Integer, db.ForeignKey("wb_users.id"), nullable=True)
    author_name = db.Column(db.String(64), nullable=False)
    content = db.Column(db.Text, nullable=False)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=utcnow, onupdate=utcnow)


class CaseShareToUser(db.Model):
    __tablename__ = "wb_case_shares"

    id = db.Column(db.Integer, primary_key=True)
    exam_id = db.Column(db.Integer, db.ForeignKey("wb_exams.id"), nullable=False)
    from_user_id = db.Column(db.Integer, db.ForeignKey("wb_users.id"), nullable=False)
    to_user_id = db.Column(db.Integer, db.ForeignKey("wb_users.id"), nullable=False)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)


class Questionnaire(db.Model):
    __tablename__ = "wb_questionnaires"

    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(160), nullable=False)
    description = db.Column(db.Text, nullable=True)
    status = db.Column(db.String(16), nullable=False, default="active")
    allow_non_patient = db.Column(db.Boolean, nullable=False, default=False)
    open_from = db.Column(db.DateTime, nullable=True)
    open_until = db.Column(db.DateTime, nullable=True)
    created_by_user_id = db.Column(db.Integer, db.ForeignKey("wb_users.id"), nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    updated_at = db.Column(db.DateTime, nullable=False, default=utcnow, onupdate=utcnow)


class Question(db.Model):
    __tablename__ = "wb_questions"

    id = db.Column(db.Integer, primary_key=True)
    questionnaire_id = db.Column(db.Integer, db.ForeignKey("wb_questionnaires.id"), nullable=False)
    sort_order = db.Column(db.Integer, nullable=False, default=0)
    q_type = db.Column(db.String(16), nullable=False)
    title = db.Column(db.String(300), nullable=False)
    options_json = db.Column(db.Text, nullable=False, default="[]")
    is_active = db.Column(db.Boolean, nullable=False, default=True)


class QuestionnaireAssignment(db.Model):
    __tablename__ = "wb_questionnaire_assignments"

    id = db.Column(db.Integer, primary_key=True)
    questionnaire_id = db.Column(db.Integer, db.ForeignKey("wb_questionnaires.id"), nullable=False)
    patient_id = db.Column(db.Integer, db.ForeignKey("wb_patients.id"), nullable=False)
    token = db.Column(db.String(64), nullable=False, unique=True, index=True)
    status = db.Column(db.String(16), nullable=False, default="pending")
    sent_by_user_id = db.Column(db.Integer, db.ForeignKey("wb_users.id"), nullable=True)
    sent_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    completed_at = db.Column(db.DateTime, nullable=True)


class QuestionnaireResponse(db.Model):
    __tablename__ = "wb_questionnaire_responses"

    id = db.Column(db.Integer, primary_key=True)
    questionnaire_id = db.Column(db.Integer, db.ForeignKey("wb_questionnaires.id"), nullable=False)
    assignment_id = db.Column(db.Integer, db.ForeignKey("wb_questionnaire_assignments.id"), nullable=True)
    responder_patient_id = db.Column(db.Integer, db.ForeignKey("wb_patients.id"), nullable=True)
    responder_user_id = db.Column(db.Integer, db.ForeignKey("wb_users.id"), nullable=True)
    responder_name = db.Column(db.String(64), nullable=True)
    responder_cookie_id = db.Column(db.String(128), nullable=True)
    responder_ip = db.Column(db.String(64), nullable=True)
    submitted_at = db.Column(db.DateTime, nullable=False, default=utcnow)


class QuestionnaireAnswer(db.Model):
    __tablename__ = "wb_questionnaire_answers"

    id = db.Column(db.Integer, primary_key=True)
    response_id = db.Column(db.Integer, db.ForeignKey("wb_questionnaire_responses.id"), nullable=False)
    question_id = db.Column(db.Integer, db.ForeignKey("wb_questions.id"), nullable=False)
    answer_json = db.Column(db.Text, nullable=False, default="null")


class AiChatSession(db.Model):
    __tablename__ = "wb_ai_chat_sessions"

    id = db.Column(db.Integer, primary_key=True)
    session_token = db.Column(db.String(64), unique=True, nullable=False, index=True)
    patient_id = db.Column(db.Integer, db.ForeignKey("wb_patients.id"), nullable=True)
    ip_address = db.Column(db.String(64), nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)


class AiChatMessage(db.Model):
    __tablename__ = "wb_ai_chat_messages"

    id = db.Column(db.Integer, primary_key=True)
    session_id = db.Column(db.Integer, db.ForeignKey("wb_ai_chat_sessions.id"), nullable=False, index=True)
    role = db.Column(db.String(16), nullable=False)
    content = db.Column(db.Text, nullable=False)
    inference_context = db.Column(db.Text, nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)

    session = db.relationship("AiChatSession", backref=db.backref("messages", cascade="all, delete-orphan", order_by="AiChatMessage.id"))


def current_user():
    uid = session.get("uid")
    if not uid:
        return None
    user = db.session.get(User, uid)
    if not user or not user.is_active:
        session.pop("uid", None)
        return None
    return user


@app.before_request
def bind_user():
    g.current_user = current_user()


def login_required_api(view):
    @wraps(view)
    def wrapper(*args, **kwargs):
        if not g.current_user:
            return api_error("请先登录", status=401, code="unauthorized")
        return view(*args, **kwargs)

    return wrapper


def admin_required_api(view):
    @wraps(view)
    def wrapper(*args, **kwargs):
        if not g.current_user:
            return api_error("请先登录", status=401, code="unauthorized")
        if g.current_user.role != "admin":
            return api_error("需要管理员权限", status=403, code="forbidden")
        return view(*args, **kwargs)

    return wrapper


def module_allowed(module_name):
    user = g.current_user
    if not user:
        return False
    if user.role == "admin":
        return True
    return module_name in user.modules()


def patient_display_name(patient):
    return patient.name or f"患者-{patient.id}"


def serialize_message(msg):
    return {
        "id": msg.id,
        "conversation_id": msg.conversation_id,
        "sender_kind": msg.sender_kind,
        "sender_user_id": msg.sender_user_id,
        "sender_name": msg.sender_name,
        "message_type": msg.message_type,
        "content": msg.content,
        "payload": json_loads(msg.payload_json, {}) or {},
        "created_at": iso(msg.created_at),
    }


def compute_unread_for_participant(part):
    last_read = part.last_read_message_id or 0
    return (
        Message.query.filter(
            Message.conversation_id == part.conversation_id,
            Message.id > last_read,
            or_(Message.sender_kind != "user", Message.sender_user_id != part.user_id),
        )
        .count()
    )


def conversation_name(conversation):
    if conversation.type == "patient" and conversation.patient_id:
        patient = db.session.get(Patient, conversation.patient_id)
        if patient:
            return f"{patient_display_name(patient)}（患者）"
    return conversation.name or f"会话-{conversation.id}"


def serialize_conversation(conversation, user_id):
    participant = ConversationParticipant.query.filter_by(conversation_id=conversation.id, user_id=user_id).first()
    last_message = Message.query.filter_by(conversation_id=conversation.id).order_by(Message.id.desc()).first()
    unread = compute_unread_for_participant(participant) if participant else 0
    return {
        "id": conversation.id,
        "type": conversation.type,
        "name": conversation_name(conversation),
        "patient_id": conversation.patient_id,
        "updated_at": iso(conversation.updated_at),
        "unread": unread,
        "last_message": serialize_message(last_message) if last_message else None,
    }


def get_user_patient_unread_map(user_id):
    unread_map = defaultdict(int)
    participants = ConversationParticipant.query.join(
        Conversation, Conversation.id == ConversationParticipant.conversation_id
    ).filter(
        ConversationParticipant.user_id == user_id,
        Conversation.type == "patient",
    ).all()

    for part in participants:
        conv = db.session.get(Conversation, part.conversation_id)
        last_read = part.last_read_message_id or 0
        unread = (
            Message.query.filter(
                Message.conversation_id == conv.id,
                Message.id > last_read,
                or_(Message.sender_kind != "user", Message.sender_user_id != user_id),
            )
            .count()
        )
        if conv.patient_id:
            unread_map[conv.patient_id] += unread

    return unread_map


def serialize_patient_row(patient, unread_map):
    latest_exam = (
        Exam.query.filter_by(patient_id=patient.id)
        .order_by(Exam.created_at.desc(), Exam.id.desc())
        .first()
    )
    last_followup_exam = (
        Exam.query.filter(Exam.patient_id == patient.id, Exam.status == "reviewed")
        .order_by(Exam.reviewed_at.desc(), Exam.id.desc())
        .first()
    )

    status = "follow_up"
    if latest_exam and latest_exam.status == "pending_review":
        status = "pending_review"
    elif unread_map.get(patient.id, 0) > 0:
        status = "has_message"

    return {
        "id": patient.id,
        "name": patient_display_name(patient),
        "age": patient.age,
        "sex": patient.sex,
        "phone": patient.phone,
        "email": patient.email,
        "status": status,
        "status_text": {"follow_up": "随访中", "pending_review": "待复核", "has_message": "有消息"}[status],
        "unread_count": unread_map.get(patient.id, 0),
        "exam_count": Exam.query.filter_by(patient_id=patient.id).count(),
        "last_exam_date": iso(latest_exam.created_at if latest_exam else None),
        "last_followup": iso(last_followup_exam.reviewed_at if last_followup_exam else None),
        "portal_url": url_for("public_portal_page", token=patient.portal_token, _external=True),
        "updated_at": iso(patient.updated_at),
    }


def serialize_exam_row(exam):
    inference = json_loads(exam.inference_json, {}) or {}
    cervical_metric = inference.get("_cervical_metric") if isinstance(inference, dict) else None
    return {
        "id": exam.id,
        "patient_id": exam.patient_id,
        "patient_name": patient_display_name(exam.patient) if exam.patient else "-",
        "upload_date": iso(exam.created_at),
        "created_at": iso(exam.created_at),
        "status": exam.status,
        "spine_class": exam.spine_class,
        "spine_class_text": spine_class_text(exam.spine_class),
        "spine_class_confidence": exam.spine_class_confidence,
        "cobb_angle": exam.cobb_angle,
        "curve_value": exam.curve_value,
        "severity_label": exam.severity_label,
        "improvement_value": exam.improvement_value,
        "image_url": url_for("static", filename=(exam.inference_image_path or exam.image_path)),
        "raw_image_url": url_for("static", filename=exam.image_path),
        "inference_image_url": url_for("static", filename=exam.inference_image_path) if exam.inference_image_path else None,
        "cervical_avg_ratio": cervical_metric.get("avg_ratio") if isinstance(cervical_metric, dict) else None,
        "cervical_assessment": cervical_metric.get("assessment") if isinstance(cervical_metric, dict) else None,
    }


def serialize_comment(comment):
    return {
        "id": comment.id,
        "author_name": comment.author_name,
        "author_kind": comment.author_kind,
        "content": comment.content,
        "created_at": iso(comment.created_at),
    }


def serialize_event(event):
    return {
        "id": event.id,
        "event_type": event.event_type,
        "title": event.title,
        "message": event.message,
        "level": event.level,
        "patient_id": event.patient_id,
        "exam_id": event.exam_id,
        "ref": json_loads(event.ref_json, {}) or {},
        "created_at": iso(event.created_at),
    }


def serialize_schedule(item):
    patient = db.session.get(Patient, item.patient_id)
    return {
        "id": item.id,
        "patient_id": item.patient_id,
        "patient_name": patient_display_name(patient) if patient else "-",
        "title": item.title,
        "note": item.note,
        "scheduled_at": iso(item.scheduled_at),
        "status": item.status,
    }


def serialize_question(item):
    options = json_loads(item.options_json, []) or []
    constraint = "any"
    constraint_hint = ""
    if item.q_type == "text" and isinstance(options, list) and options and isinstance(options[0], dict):
        constraint = (options[0].get("constraint") or "any").strip() or "any"
        constraint_hint = (options[0].get("constraint_hint") or "").strip()
    return {
        "id": item.id,
        "sort_order": item.sort_order,
        "q_type": item.q_type,
        "title": item.title,
        "options": options,
        "constraint": constraint,
        "constraint_hint": constraint_hint,
    }


def normalize_question_payload(item):
    q_type_raw = (item.get("q_type") or "").strip().lower()
    q_title = (item.get("title") or "").strip()
    if not q_title:
        raise ValueError("题目标题不能为空")

    options_raw = item.get("options") if isinstance(item.get("options"), list) else []
    if q_type_raw in {"single", "multi", "choice"}:
        if q_type_raw == "multi":
            q_type = "multi"
        else:
            mode = (item.get("choice_mode") or "single").strip().lower()
            q_type = "multi" if mode == "multi" else "single"
        options = [str(opt).strip() for opt in options_raw if str(opt).strip()]
        if len(options) < 2:
            raise ValueError("选择题至少保留两个选项")
        return q_type, q_title, options

    if q_type_raw in {"text", "blank"}:
        q_type = "text"
        if q_type_raw == "blank":
            constraint = (item.get("constraint") or "any").strip() or "any"
            constraint_hint = (item.get("constraint_hint") or "").strip()
            if isinstance(options_raw, list) and options_raw and isinstance(options_raw[0], dict):
                constraint = (options_raw[0].get("constraint") or constraint).strip() or "any"
                constraint_hint = (options_raw[0].get("constraint_hint") or constraint_hint).strip()
            return q_type, q_title, [{"constraint": constraint, "constraint_hint": constraint_hint}]
        return q_type, q_title, options_raw if isinstance(options_raw, list) else []

    raise ValueError(f"题目类型不支持：{q_type_raw}")


def ws_send(ws, payload):
    try:
        ws.send(json_dumps(payload))
        return True
    except Exception:
        return False


def ws_subscribe(ws, channel):
    with WS_LOCK:
        WS_CHANNELS[channel].add(ws)
        meta = WS_META.setdefault(ws, {"channels": set(), "user": {"kind": "guest", "name": "访客"}})
        meta["channels"].add(channel)


def ws_unsubscribe(ws, channel):
    with WS_LOCK:
        if channel in WS_CHANNELS and ws in WS_CHANNELS[channel]:
            WS_CHANNELS[channel].discard(ws)
            if not WS_CHANNELS[channel]:
                WS_CHANNELS.pop(channel, None)
        meta = WS_META.get(ws)
        if meta:
            meta["channels"].discard(channel)


def ws_cleanup(ws):
    with WS_LOCK:
        meta = WS_META.pop(ws, None)
        channels = list(meta["channels"]) if meta else []
    for channel in channels:
        ws_unsubscribe(ws, channel)


def ws_broadcast(channel, payload, exclude=None):
    with WS_LOCK:
        targets = list(WS_CHANNELS.get(channel, set()))

    dead = []
    for client in targets:
        if exclude is not None and client is exclude:
            continue
        if not ws_send(client, payload):
            dead.append(client)

    for client in dead:
        ws_cleanup(client)


@sock.route("/ws")
def ws_handler(ws):
    WS_META[ws] = {"channels": set(), "user": {"kind": "guest", "name": "访客"}}
    try:
        while True:
            raw = ws.receive()
            if raw is None:
                break

            data = json_loads(raw, {}) or {}
            msg_type = data.get("type")

            if msg_type == "hello":
                meta = WS_META.setdefault(ws, {"channels": set(), "user": {}})
                meta["user"] = {
                    "kind": data.get("kind") or "guest",
                    "name": data.get("name") or "访客",
                    "id": data.get("id"),
                }
                ws_send(ws, {"type": "hello_ack", "ts": iso(utcnow())})
                continue

            if msg_type == "ping":
                ws_send(ws, {"type": "pong", "ts": iso(utcnow())})
                continue

            if msg_type == "subscribe":
                channels = data.get("channels") if isinstance(data.get("channels"), list) else []
                if data.get("channel"):
                    channels.append(data["channel"])
                for ch in channels:
                    if isinstance(ch, str) and ch.strip():
                        ws_subscribe(ws, ch.strip())
                ws_send(ws, {"type": "subscribed", "channels": channels})
                continue

            if msg_type == "unsubscribe":
                if data.get("channel"):
                    ws_unsubscribe(ws, data["channel"])
                continue

            if msg_type in {"field_focus", "field_change", "form_submit", "typing"}:
                channel = data.get("channel")
                if not channel:
                    continue
                meta = WS_META.get(ws, {"user": {"kind": "guest", "name": "访客"}})
                ws_broadcast(
                    channel,
                    {
                        "type": msg_type,
                        "channel": channel,
                        "actor": meta.get("user"),
                        "payload": data.get("payload", {}),
                        "ts": iso(utcnow()),
                    },
                    exclude=ws,
                )
    finally:
        ws_cleanup(ws)


def make_qr_data_url(text):
    qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=6, border=2)
    qr.add_data(text)
    qr.make(fit=True)
    image = qr.make_image(fill_color="black", back_color="white")
    buf = io.BytesIO()
    image.save(buf, format="PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("utf-8")


def save_upload(file_obj):
    if not file_obj:
        raise ValueError("缺少上传文件")

    original = secure_filename(file_obj.filename or "upload.png")
    ext = Path(original).suffix.lower()
    if ext not in ALLOWED_UPLOAD_EXT:
        raise ValueError("仅支持 png/jpg/jpeg/bmp/webp")

    filename = f"{uuid.uuid4().hex}{ext}"
    destination = UPLOAD_DIR / filename
    file_obj.save(destination)
    return f"uploads/{filename}"


def guess_image_ext(mimetype):
    mime = str(mimetype or "").lower().strip()
    if mime in ("image/jpeg", "image/jpg"):
        return ".jpg"
    if mime == "image/webp":
        return ".webp"
    if mime == "image/bmp":
        return ".bmp"
    return ".png"


def decode_base64_image(raw_value):
    raw = str(raw_value or "").strip()
    if not raw:
        return None, None

    mimetype = None
    b64_part = raw
    if raw.startswith("data:"):
        header, sep, tail = raw.partition(",")
        if not sep:
            return None, None
        b64_part = tail
        mime = header[5:].split(";")[0].strip()
        mimetype = mime or None

    b64_part = b64_part.strip()
    if not b64_part:
        return None, mimetype

    pad = len(b64_part) % 4
    if pad:
        b64_part += "=" * (4 - pad)

    try:
        content = base64.b64decode(b64_part, validate=False)
    except Exception:
        return None, mimetype
    if not content:
        return None, mimetype
    return content, mimetype


def save_inference_image(exam, payload):
    b64_value = extract_inference_value(
        payload,
        [
            "result_image_base64",
            "overlay_image_base64",
            "rendered_image_base64",
            "image_base64",
            "overlay_base64",
        ],
    )
    if not b64_value:
        return None

    mime_value = extract_inference_value(
        payload,
        [
            "result_image_mimetype",
            "overlay_image_mimetype",
            "image_mimetype",
            "mime_type",
            "mimetype",
            "content_type",
        ],
    )

    content, mime_from_data = decode_base64_image(b64_value)
    if not content:
        return None

    ext = guess_image_ext(mime_from_data or mime_value)
    folder = UPLOAD_DIR / "inference"
    folder.mkdir(parents=True, exist_ok=True)
    filename = f"infer_exam_{exam.id}_{uuid.uuid4().hex[:10]}{ext}"
    destination = folder / filename

    with open(destination, "wb") as fp:
        fp.write(content)

    old_rel_path = exam.inference_image_path
    new_rel_path = f"uploads/inference/{filename}"
    exam.inference_image_path = new_rel_path

    if old_rel_path and old_rel_path != new_rel_path:
        try:
            old_path = BASE_DIR / "static" / old_rel_path
            if old_path.exists():
                old_path.unlink()
        except Exception:
            pass

    return new_rel_path


def save_generated_inference_image(exam, image_obj):
    if image_obj is None:
        return None
    folder = UPLOAD_DIR / "inference"
    folder.mkdir(parents=True, exist_ok=True)
    filename = f"infer_exam_{exam.id}_{uuid.uuid4().hex[:10]}.png"
    destination = folder / filename
    image_obj.save(destination, format="PNG")

    old_rel_path = exam.inference_image_path
    new_rel_path = f"uploads/inference/{filename}"
    exam.inference_image_path = new_rel_path

    if old_rel_path and old_rel_path != new_rel_path:
        try:
            old_path = BASE_DIR / "static" / old_rel_path
            if old_path.exists():
                old_path.unlink()
        except Exception:
            pass
    return new_rel_path


def _safe_point(raw):
    if isinstance(raw, (list, tuple)) and len(raw) >= 2:
        x = to_float(raw[0], None)
        y = to_float(raw[1], None)
        if x is not None and y is not None:
            return (x, y)
    if isinstance(raw, dict):
        x = to_float(raw.get("x"), None)
        y = to_float(raw.get("y"), None)
        if x is not None and y is not None:
            return (x, y)
    return None


def extract_cervical_triplets(payload):
    keypoints = extract_inference_value(payload, ["keypoints", "points", "landmarks"])
    if not keypoints:
        return []

    points = []
    if isinstance(keypoints, list):
        for item in keypoints:
            pt = _safe_point(item)
            if pt:
                points.append(pt)
    elif isinstance(keypoints, dict):
        for value in keypoints.values():
            if isinstance(value, list):
                if len(value) >= 3 and all(_safe_point(v) for v in value[:3]):
                    p1 = _safe_point(value[0])
                    p2 = _safe_point(value[1])
                    p3 = _safe_point(value[2])
                    if p1 and p2 and p3:
                        points.extend([p1, p2, p3])
                    continue
                for item in value:
                    pt = _safe_point(item)
                    if pt:
                        points.append(pt)
            elif isinstance(value, dict):
                maybe_points = value.get("points")
                if isinstance(maybe_points, list):
                    for item in maybe_points:
                        pt = _safe_point(item)
                        if pt:
                            points.append(pt)

    triplets = []
    for i in range(0, len(points), 3):
        chunk = points[i : i + 3]
        if len(chunk) == 3:
            triplets.append((chunk[0], chunk[1], chunk[2]))
    return triplets


def _distance(p1, p2):
    dx = float(p1[0]) - float(p2[0])
    dy = float(p1[1]) - float(p2[1])
    return (dx * dx + dy * dy) ** 0.5


def build_cervical_metric(payload):
    triplets = extract_cervical_triplets(payload)
    segments = []
    ratios = []
    for idx, (p_left, p_mid, p_right) in enumerate(triplets):
        left_len = _distance(p_left, p_mid)
        right_len = _distance(p_mid, p_right)
        ratio = None
        if right_len > 1e-6:
            ratio = left_len / right_len
            ratios.append(ratio)
        segments.append(
            {
                "level": f"C{idx + 3}",
                "left_len": left_len,
                "right_len": right_len,
                "ratio": ratio,
                "points": {
                    "left": [p_left[0], p_left[1]],
                    "mid": [p_mid[0], p_mid[1]],
                    "right": [p_right[0], p_right[1]],
                },
            }
        )

    avg_ratio = None
    assessment = "无法评估"
    if ratios:
        avg_ratio = sum(ratios) / len(ratios)
        if 0.83 <= avg_ratio <= 1.11:
            assessment = "良好"
        elif avg_ratio < 0.83:
            assessment = "抗过载力低，容易颈痛"
        else:
            assessment = "容易发生颈椎疾病"

    return {
        "avg_ratio": avg_ratio,
        "assessment": assessment,
        "segment_count": len(segments),
        "segments": segments,
    }


def draw_cervical_overlay_image(exam, payload):
    triplets = extract_cervical_triplets(payload)
    if not triplets:
        return None
    raw_path = BASE_DIR / "static" / exam.image_path
    if not raw_path.exists():
        return None

    image = Image.open(raw_path).convert("RGB")
    draw = ImageDraw.Draw(image)
    width, height = image.size
    line_w = max(2, int(min(width, height) * 0.003))
    radius = max(3, int(min(width, height) * 0.006))

    for idx, (p_left, p_mid, p_right) in enumerate(triplets):
        draw.line([p_left, p_mid], fill=(0, 217, 255), width=line_w)
        draw.line([p_mid, p_right], fill=(255, 176, 0), width=line_w)

        for point, color in ((p_left, (0, 217, 255)), (p_mid, (255, 255, 255)), (p_right, (255, 176, 0))):
            x, y = point
            draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=color, outline=(20, 20, 20), width=1)

        left_len = _distance(p_left, p_mid)
        right_len = _distance(p_mid, p_right)
        ratio_text = "--"
        if right_len > 1e-6:
            ratio_text = f"{(left_len / right_len):.2f}"
        label = f"C{idx + 3} {ratio_text}"
        tx = p_mid[0] + 8
        ty = p_mid[1] - 16
        draw.text((tx + 1, ty + 1), label, fill=(0, 0, 0))
        draw.text((tx, ty), label, fill=(255, 255, 255))
    return image


def extract_inference_value(payload, keys):
    keyset = {str(k) for k in (keys or [])}

    def walk(node):
        if isinstance(node, dict):
            for k in keyset:
                if k in node and node.get(k) not in (None, ""):
                    return node.get(k)
            for v in node.values():
                found = walk(v)
                if found not in (None, ""):
                    return found
        elif isinstance(node, list):
            for item in node:
                found = walk(item)
                if found not in (None, ""):
                    return found
        return None

    return walk(payload)


def extract_inference_number(payload, keys):
    value = extract_inference_value(payload, keys)
    return to_float(value, None)


def normalize_spine_class(raw_name):
    name = str(raw_name or "").strip().lower()
    if name in {"lumbar", "lumbar_spine", "l-spine", "lspine", "腰椎"}:
        return "lumbar"
    if name in {"cervical", "cervical_spine", "c-spine", "cspine", "颈椎"}:
        return "cervical"
    # 兼容远程分类返回中夹带注释或额外文本的场景
    if "lumbar" in name or "腰" in name:
        return "lumbar"
    if "cervical" in name or "颈" in name:
        return "cervical"
    return None


def spine_class_text(class_name):
    normalized = normalize_spine_class(class_name)
    if normalized == "lumbar":
        return "腰椎"
    if normalized == "cervical":
        return "颈椎"
    return "未分类"


def resolve_review_owner_user_id(exam):
    if exam.review_owner_user_id:
        return exam.review_owner_user_id
    patient = exam.patient if exam else None
    if patient and patient.created_by_user_id:
        return patient.created_by_user_id
    return None


def can_user_access_exam_review(user, exam):
    if not user or not exam:
        return False
    if user.role == "admin":
        return True
    owner_id = resolve_review_owner_user_id(exam)
    return owner_id is not None and int(owner_id) == int(user.id)


def severity_label(cobb_angle):
    if cobb_angle is None:
        return None
    if cobb_angle < 20:
        return "轻度"
    if cobb_angle < 40:
        return "中度"
    return "重度"


def build_remote_url(path):
    base = str(app.config.get("REMOTE_INFER_BASE") or "").strip()
    if not base:
        raise RuntimeError("REMOTE_INFER_BASE 未配置")
    path_part = path if str(path).startswith("/") else f"/{path}"
    return base.rstrip("/") + path_part


# ── IP rate limiter (in-memory, per-process) ──
EXTRA_REMOTE_INFER_MODELS = {
    "clavicle": {
        "paths": ["/infer/clavicle", "/infer/lockbone", "/infer/suogu", "/infer/clavicle_t1"],
        "weight_path": "weights/锁骨",
    },
    "t1": {
        "paths": ["/infer/t1", "/infer/t1locator", "/infer/clavicle_t1"],
        "weight_path": "weights/T1",
    },
    "pelvis": {
        "paths": ["/infer/pelvis", "/infer/pelvic", "/infer/pelvic_tilt"],
        "weight_path": "weights/骨盆",
    },
}


def _as_xy_point(value):
    if isinstance(value, (list, tuple)) and len(value) >= 2:
        x = to_float(value[0], None)
        y = to_float(value[1], None)
        if x is not None and y is not None:
            return (x, y)
    if isinstance(value, dict):
        x = to_float(value.get("x"), None)
        y = to_float(value.get("y"), None)
        if x is not None and y is not None:
            return (x, y)
        x = to_float(value.get("cx"), None)
        y = to_float(value.get("cy"), None)
        if x is not None and y is not None:
            return (x, y)
    return None


def _collect_named_points(node, name_hints, out):
    if isinstance(node, dict):
        for key, value in node.items():
            key_text = str(key).lower()
            if any(hint in key_text for hint in name_hints):
                point = _as_xy_point(value)
                if point is not None:
                    out.append(point)
            _collect_named_points(value, name_hints, out)
    elif isinstance(node, list):
        for item in node:
            _collect_named_points(item, name_hints, out)


def _extract_pelvic_tilt_from_payload(payload):
    angle = extract_inference_number(
        payload,
        [
            "pelvic_tilt_deg",
            "pelvic_tilt_angle",
            "pelvic_tilt",
            "tilt_angle_deg",
            "tilt_angle",
            "tilt_deg",
            "angle_deg",
        ],
    )
    if angle is not None:
        return {
            "angle_deg": angle,
            "abs_angle_deg": abs(float(angle)),
            "source": "remote",
        }

    left_points = []
    right_points = []
    _collect_named_points(payload, {"left", "l_", "lt", "iliac_l", "pelvis_l", "hip_l"}, left_points)
    _collect_named_points(payload, {"right", "r_", "rt", "iliac_r", "pelvis_r", "hip_r"}, right_points)

    left = left_points[0] if left_points else None
    right = right_points[0] if right_points else None
    if left is None or right is None:
        return None

    dx = float(right[0] - left[0])
    dy = float(right[1] - left[1])
    angle_deg = math.degrees(math.atan2(dy, dx))
    return {
        "angle_deg": round(angle_deg, 4),
        "abs_angle_deg": round(abs(angle_deg), 4),
        "left_point": [round(float(left[0]), 3), round(float(left[1]), 3)],
        "right_point": [round(float(right[0]), 3), round(float(right[1]), 3)],
        "source": "computed",
    }


def attach_extra_remote_models(payload, b64_image):
    if not isinstance(payload, dict) or not b64_image:
        return None

    aux = payload.get("_extra_models")
    if not isinstance(aux, dict):
        aux = {}
        payload["_extra_models"] = aux

    timeout = app.config.get("REMOTE_INFER_TIMEOUT", 60)
    for model_name, cfg in EXTRA_REMOTE_INFER_MODELS.items():
        req_payload = {
            "image_base64": b64_image,
            "model_name": model_name,
            "model_path": cfg["weight_path"],
            "weights_path": cfg["weight_path"],
        }
        model_res = None
        model_error = None
        for infer_path in cfg["paths"]:
            try:
                trial = requests.post(
                    build_remote_url(infer_path),
                    json=req_payload,
                    timeout=timeout,
                )
                if trial.status_code == 404:
                    continue
                if not trial.ok:
                    model_error = f"HTTP {trial.status_code}"
                    break
                candidate = trial.json() if trial.content else {}
                if isinstance(candidate, dict) and candidate.get("status") == "error":
                    model_error = candidate.get("message") or "remote returned error"
                    break
                model_res = candidate
                break
            except Exception as exc:
                model_error = str(exc)
                break

        if model_res is not None:
            aux[model_name] = model_res
        elif model_error:
            aux[model_name] = {"status": "error", "message": model_error}

    pelvic_payload = aux.get("pelvis")
    pelvic_metric = None
    if isinstance(pelvic_payload, dict):
        pelvic_metric = _extract_pelvic_tilt_from_payload(pelvic_payload)
    if pelvic_metric is None:
        pelvic_metric = _extract_pelvic_tilt_from_payload(payload)
    if pelvic_metric is not None:
        payload["_pelvic_tilt_metric"] = pelvic_metric
        return pelvic_metric
    return None


_anon_infer_log = defaultdict(list)  # ip -> [timestamp, ...]
_anon_infer_lock = threading.Lock()


def check_anon_rate_limit(ip):
    limit = app.config.get("ANON_INFER_LIMIT", 3)
    window = app.config.get("ANON_INFER_WINDOW", 3600)
    now = datetime.utcnow()
    cutoff = now - timedelta(seconds=window)
    with _anon_infer_lock:
        timestamps = _anon_infer_log[ip]
        timestamps[:] = [t for t in timestamps if t > cutoff]
        if len(timestamps) >= limit:
            return False
        timestamps.append(now)
    return True


def run_anonymous_inference(image_bytes):
    """Run inference without creating Patient/Exam records. Returns dict with results."""
    b64_image = base64.b64encode(image_bytes).decode("utf-8")

    classify_payload = {"image_base64": b64_image}
    classify_response = requests.post(
        build_remote_url("/classify/xray"),
        json=classify_payload,
        timeout=app.config["REMOTE_INFER_TIMEOUT"],
    )
    if not classify_response.ok:
        raise RuntimeError(f"远程分类失败 HTTP {classify_response.status_code}")
    classify_json = classify_response.json() if classify_response.content else {}
    if isinstance(classify_json, dict) and classify_json.get("status") == "error":
        raise RuntimeError(classify_json.get("message") or "远程分类返回错误")

    class_name = normalize_spine_class(extract_inference_value(classify_json, ["class_name", "class", "label", "type"]))
    class_id = extract_inference_number(classify_json, ["class_id", "id"])
    class_confidence = extract_inference_number(classify_json, ["confidence", "probability", "prob", "score"])

    class_id_int = None
    if class_id is not None:
        try:
            class_id_int = int(class_id)
        except (TypeError, ValueError, OverflowError):
            class_id_int = None

    if not class_name and class_id_int == 0:
        class_name = "cervical"
    elif not class_name and class_id_int == 1:
        class_name = "lumbar"

    if class_name == "cervical":
        infer_paths = ["/infer/tansit"]
    elif class_name == "lumbar":
        infer_paths = ["/infer/l4l5locator", "/infer/l4l5"]
    else:
        raise RuntimeError("无法识别脊柱类型，未执行推理")

    infer_payload = {"image_base64": b64_image, "conf": 0.3}
    response = None
    for infer_path in infer_paths:
        trial = requests.post(
            build_remote_url(infer_path),
            json=infer_payload,
            timeout=app.config["REMOTE_INFER_TIMEOUT"],
        )
        if trial.status_code == 404:
            continue
        response = trial
        break

    if response is None:
        raise RuntimeError("远程预测接口不可用")
    if not response.ok:
        raise RuntimeError(f"远程推理失败 HTTP {response.status_code}")

    payload = response.json() if response.content else {}
    pelvic_metric = attach_extra_remote_models(payload, b64_image)
    if isinstance(payload, dict) and payload.get("status") == "error":
        raise RuntimeError(payload.get("message") or "远程推理返回错误")

    if isinstance(payload, dict):
        payload["_classification"] = {
            "class_name": class_name,
            "class_text": spine_class_text(class_name),
            "class_id": class_id_int,
            "confidence": class_confidence,
        }

    result = {
        "spine_class": class_name,
        "spine_class_text": spine_class_text(class_name),
        "spine_class_confidence": class_confidence,
    }

    if class_name == "cervical":
        cervical_metric = build_cervical_metric(payload)
        if isinstance(payload, dict):
            payload["_cervical_metric"] = cervical_metric
        result["cervical_metric"] = cervical_metric
    else:
        cobb = extract_inference_number(payload, ["cobb_deg", "cobb_angle", "cobb", "angle", "max_cobb"])
        curve = extract_inference_number(payload, ["curvature_deg", "curvature", "curve", "spinal_curvature", "curve_value"])
        result["cobb_angle"] = cobb
        result["curve_value"] = curve
        result["severity_label"] = severity_label(cobb)

    # Include overlay image if available
    overlay_b64 = None
    if isinstance(payload, dict):
        overlay_b64 = payload.get("overlay_image") or payload.get("result_image") or payload.get("image_base64")
    result["overlay_image"] = overlay_b64
    result["pelvic_tilt_metric"] = pelvic_metric
    if isinstance(pelvic_metric, dict):
        result["pelvic_tilt_deg"] = pelvic_metric.get("angle_deg")
        result["pelvic_tilt_abs_deg"] = pelvic_metric.get("abs_angle_deg")
    result["inference_json"] = payload

    return result


# ── StepFun LLM helper ──
STEPFUN_SYSTEM_PROMPT = (
    "你是一位专业的脊柱健康AI助手。你只回答与脊柱健康、脊柱侧弯（scoliosis）、"
    "颈椎（cervical spine）、腰椎（lumbar spine）、Cobb角、脊柱矫正和康复相关的问题。"
    "对于与脊柱健康无关的问题，请礼貌地拒绝并引导用户回到脊柱健康话题。"
    "根据用户提供的推理数据（如有），给出专业但通俗易懂的解读和建议。"
    "你的回答应简明扼要，条理清晰。重要：你不是医生，你的建议不能替代专业医疗诊断。"
)


def call_stepfun(messages, inference_context=None):
    api_base = app.config.get("STEPFUN_API_BASE", "").rstrip("/")
    api_key = app.config.get("STEPFUN_API_KEY", "")
    model = app.config.get("STEPFUN_MODEL", "step-1-8k")

    if not api_base or not api_key:
        raise RuntimeError("StepFun API 未配置")

    system_content = STEPFUN_SYSTEM_PROMPT
    if inference_context:
        system_content += f"\n\n以下是该用户最近的脊柱推理检测数据，请在回答时参考：\n{json.dumps(inference_context, ensure_ascii=False, indent=2)}"

    full_messages = [{"role": "system", "content": system_content}] + messages

    resp = requests.post(
        f"{api_base}/chat/completions",
        json={"model": model, "messages": full_messages},
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        timeout=60,
    )
    if not resp.ok:
        raise RuntimeError(f"StepFun API 调用失败 HTTP {resp.status_code}")
    data = resp.json()
    choices = data.get("choices") or []
    if not choices:
        raise RuntimeError("StepFun API 返回空结果")
    return choices[0].get("message", {}).get("content", "")


def get_client_ip():
    return request.headers.get("X-Forwarded-For", request.remote_addr or "unknown").split(",")[0].strip()


def call_stepfun_stream(messages, inference_context=None):
    """Generator yielding text chunks from StepFun streaming API."""
    api_base = app.config.get("STEPFUN_API_BASE", "").rstrip("/")
    api_key = app.config.get("STEPFUN_API_KEY", "")
    model = app.config.get("STEPFUN_MODEL", "step-1-8k")

    if not api_base or not api_key:
        raise RuntimeError("StepFun API 未配置")

    system_content = STEPFUN_SYSTEM_PROMPT
    if inference_context:
        system_content += f"\n\n以下是该用户最近的脊柱推理检测数据，请在回答时参考：\n{json.dumps(inference_context, ensure_ascii=False, indent=2)}"

    full_messages = [{"role": "system", "content": system_content}] + messages

    resp = requests.post(
        f"{api_base}/chat/completions",
        json={"model": model, "messages": full_messages, "stream": True},
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        timeout=120,
        stream=True,
    )
    if not resp.ok:
        raise RuntimeError(f"StepFun API 调用失败 HTTP {resp.status_code}")

    for line in resp.iter_lines():
        if not line:
            continue
        line_str = line.decode("utf-8")
        if not line_str.startswith("data: "):
            continue
        data_str = line_str[6:].strip()
        if data_str == "[DONE]":
            break
        try:
            chunk_data = json.loads(data_str)
            delta = chunk_data.get("choices", [{}])[0].get("delta", {}).get("content", "")
            if delta:
                yield delta
        except (json.JSONDecodeError, IndexError, KeyError):
            continue


def run_remote_inference(exam):
    job = InferenceJob(exam_id=exam.id, status="queued", queued_at=utcnow())
    db.session.add(job)
    db.session.commit()

    job.status = "running"
    job.started_at = utcnow()
    db.session.commit()

    image_abs = BASE_DIR / "static" / exam.image_path
    started_at = utcnow()

    try:
        with open(image_abs, "rb") as fp:
            raw_bytes = fp.read()

        b64_image = base64.b64encode(raw_bytes).decode("utf-8")

        classify_payload = {"image_base64": b64_image}
        classify_response = requests.post(
            build_remote_url("/classify/xray"),
            json=classify_payload,
            timeout=app.config["REMOTE_INFER_TIMEOUT"],
        )
        if not classify_response.ok:
            raise RuntimeError(f"远程分类失败 HTTP {classify_response.status_code}")
        classify_json = classify_response.json() if classify_response.content else {}
        if isinstance(classify_json, dict) and classify_json.get("status") == "error":
            raise RuntimeError(classify_json.get("message") or "远程分类返回错误")

        class_name = normalize_spine_class(extract_inference_value(classify_json, ["class_name", "class", "label", "type"]))
        class_id = extract_inference_number(classify_json, ["class_id", "id"])
        class_confidence = extract_inference_number(classify_json, ["confidence", "probability", "prob", "score"])

        class_id_int = None
        if class_id is not None:
            try:
                class_id_int = int(class_id)
            except (TypeError, ValueError, OverflowError):
                class_id_int = None

        # 远程分类约定：cervical=0, lumbar=1
        if not class_name and class_id_int == 0:
            class_name = "cervical"
        elif not class_name and class_id_int == 1:
            class_name = "lumbar"

        if class_name == "cervical":
            infer_paths = ["/infer/tansit"]
        elif class_name == "lumbar":
            infer_paths = ["/infer/l4l5locator", "/infer/l4l5"]
        else:
            raise RuntimeError("无法识别脊柱类型，未执行推理")

        infer_payload = {"image_base64": b64_image, "conf": 0.3}
        response = None
        for infer_path in infer_paths:
            trial = requests.post(
                build_remote_url(infer_path),
                json=infer_payload,
                timeout=app.config["REMOTE_INFER_TIMEOUT"],
            )
            if trial.status_code == 404:
                continue
            response = trial
            break

        if response is None:
            raise RuntimeError("远程预测接口不可用")

        elapsed = int((utcnow() - started_at).total_seconds() * 1000)
        if not response.ok:
            raise RuntimeError(f"远程推理失败 HTTP {response.status_code}")

        payload = response.json() if response.content else {}
        pelvic_metric = attach_extra_remote_models(payload, b64_image)
        if isinstance(payload, dict) and payload.get("status") == "error":
            raise RuntimeError(payload.get("message") or "远程推理返回错误")
        if isinstance(payload, dict):
            payload["_classification"] = {
                "class_name": class_name,
                "class_text": spine_class_text(class_name),
                "class_id": class_id_int,
                "confidence": class_confidence,
                "raw": classify_json,
            }

        cervical_metric = None
        if class_name == "cervical":
            cervical_metric = build_cervical_metric(payload)
            if isinstance(payload, dict):
                payload["_cervical_metric"] = cervical_metric

            try:
                generated = draw_cervical_overlay_image(exam, payload)
                if generated is not None:
                    save_generated_inference_image(exam, generated)
                else:
                    exam.inference_image_path = None
                    if isinstance(payload, dict):
                        payload["_save_image_error"] = "颈椎标注图本地重绘失败"
            except Exception as img_exc:
                if isinstance(payload, dict):
                    payload["_save_image_error"] = str(img_exc)
            cobb = None
            curve = None
        else:
            cobb = extract_inference_number(payload, ["cobb_deg", "cobb_angle", "cobb", "angle", "max_cobb"])
            curve = extract_inference_number(payload, ["curvature_deg", "curvature", "curve", "spinal_curvature", "curve_value"])
            try:
                save_inference_image(exam, payload)
            except Exception as img_exc:
                if isinstance(payload, dict):
                    payload["_save_image_error"] = str(img_exc)

        exam.inference_json = json_dumps(payload)
        exam.spine_class = class_name
        exam.spine_class_id = class_id_int
        exam.spine_class_confidence = class_confidence
        exam.cobb_angle = cobb
        exam.curve_value = curve
        exam.severity_label = severity_label(cobb) if class_name != "cervical" else None
        exam.status = "pending_review"
        exam.improvement_value = None

        if class_name == "cervical" and cervical_metric and cervical_metric.get("avg_ratio") is not None:
            prev_rows = (
                Exam.query.filter(Exam.patient_id == exam.patient_id, Exam.id != exam.id)
                .order_by(Exam.created_at.desc(), Exam.id.desc())
                .limit(20)
                .all()
            )
            prev_ratio = None
            for prev in prev_rows:
                prev_inf = json_loads(prev.inference_json, {}) or {}
                prev_metric = prev_inf.get("_cervical_metric") if isinstance(prev_inf, dict) else None
                if isinstance(prev_metric, dict) and prev_metric.get("avg_ratio") is not None:
                    prev_ratio = to_float(prev_metric.get("avg_ratio"), None)
                    if prev_ratio is not None:
                        break
            curr_dev = abs(float(cervical_metric.get("avg_ratio")) - 1.0)
            if prev_ratio is not None:
                prev_dev = abs(prev_ratio - 1.0)
                exam.improvement_value = round(prev_dev - curr_dev, 3)
        else:
            prev = (
                Exam.query.filter(
                    Exam.patient_id == exam.patient_id,
                    Exam.id != exam.id,
                    Exam.cobb_angle.isnot(None),
                )
                .order_by(Exam.created_at.desc(), Exam.id.desc())
                .first()
            )
            if prev and prev.cobb_angle is not None and cobb is not None:
                exam.improvement_value = round(prev.cobb_angle - cobb, 2)

        job.status = "success"
        job.latency_ms = elapsed
        job.finished_at = utcnow()
        db.session.commit()

        confidence_text = f"{(class_confidence * 100):.1f}%" if class_confidence is not None else "--"
        metric_text = ""
        if isinstance(pelvic_metric, dict) and pelvic_metric.get("angle_deg") is not None:
            metric_text += f", pelvic tilt {float(pelvic_metric['angle_deg']):.2f} deg"
        if class_name == "cervical" and cervical_metric and cervical_metric.get("avg_ratio") is not None:
            metric_text += f"，平均左/右比 {float(cervical_metric['avg_ratio']):.3f}"
        create_work_event(
            "inference_result",
            "推理完成",
            f"推理结果为 {spine_class_text(class_name)}，置信度为 {confidence_text}{metric_text}",
            level="info",
            patient_id=exam.patient_id,
            exam_id=exam.id,
            ref={
                "exam_id": exam.id,
                "spine_class": class_name,
                "spine_class_text": spine_class_text(class_name),
                "confidence": class_confidence,
                "pic_name": Path(exam.image_path).name if exam.image_path else "",
                "owner_name": review_owner_name(exam),
                "cervical_avg_ratio": cervical_metric.get("avg_ratio") if isinstance(cervical_metric, dict) else None,
                "cervical_assessment": cervical_metric.get("assessment") if isinstance(cervical_metric, dict) else None,
                "pelvic_tilt_deg": pelvic_metric.get("angle_deg") if isinstance(pelvic_metric, dict) else None,
                "pelvic_tilt_abs_deg": pelvic_metric.get("abs_angle_deg") if isinstance(pelvic_metric, dict) else None,
            },
        )
    except Exception as exc:
        job.status = "failed"
        job.error_message = str(exc)
        job.latency_ms = int((utcnow() - started_at).total_seconds() * 1000)
        job.finished_at = utcnow()
        exam.status = "inference_failed"
        exam.inference_json = json_dumps({"error": str(exc), "remote_base": app.config.get("REMOTE_INFER_BASE")})
        db.session.commit()
        create_work_event(
            "inference_failed",
            "推理失败",
            f"推理失败：{str(exc)}",
            level="warn",
            patient_id=exam.patient_id,
            exam_id=exam.id,
            ref={
                "exam_id": exam.id,
                "pic_name": Path(exam.image_path).name if exam.image_path else "",
                "owner_name": review_owner_name(exam),
                "error": str(exc),
            },
        )


def create_work_event(event_type, title, message, level="info", patient_id=None, exam_id=None, ref=None):
    event = WorkEvent(
        event_type=event_type,
        title=title,
        message=message,
        level=level,
        patient_id=patient_id,
        exam_id=exam_id,
        ref_json=json_dumps(ref or {}),
    )
    db.session.add(event)
    db.session.commit()
    ws_broadcast("system", {"type": "feed_new", "item": serialize_event(event)})
    ws_broadcast("system", {"type": "toast", "title": title, "message": message, "level": level})


def review_owner_name(exam):
    owner_id = resolve_review_owner_user_id(exam)
    if not owner_id:
        return "未分配医生"
    user = db.session.get(User, owner_id)
    return user.display_name if user else f"医生-{owner_id}"


def ensure_share_link(exam_id, user_id):
    link = ExamShareLink.query.filter_by(exam_id=exam_id).first()
    if link:
        if not link.is_active:
            link.is_active = True
            db.session.commit()
        return link
    link = ExamShareLink(exam_id=exam_id, token=generate_token("case_"), created_by_user_id=user_id, is_active=True)
    db.session.add(link)
    db.session.commit()
    return link


def log_share_access(link, req):
    row = ShareAccessLog(
        share_link_id=link.id,
        access_ip=req.remote_addr,
        user_agent=req.headers.get("User-Agent"),
        viewer_label=req.args.get("viewer") or "匿名访问",
    )
    db.session.add(row)
    db.session.commit()
    access = {
        "id": row.id,
        "access_ip": row.access_ip,
        "viewer_label": row.viewer_label,
        "user_agent": (row.user_agent or "")[:120],
        "accessed_at": iso(row.accessed_at),
    }
    ws_broadcast(f"share:{link.id}", {"type": "share_access", "access": access})
    ws_broadcast(f"share_exam:{link.exam_id}", {"type": "share_access", "access": access})


def get_or_create_patient_conversation(patient):
    conv = Conversation.query.filter_by(type="patient", patient_id=patient.id).first()
    if not conv:
        conv = Conversation(type="patient", name=f"{patient_display_name(patient)}随访沟通", patient_id=patient.id, updated_at=utcnow())
        db.session.add(conv)
        db.session.flush()

    doctors = User.query.filter(User.is_active.is_(True), User.role.in_(["admin", "doctor", "nurse"])).all()
    exists = {i.user_id for i in ConversationParticipant.query.filter_by(conversation_id=conv.id).all()}
    for doctor in doctors:
        if doctor.id in exists:
            continue
        db.session.add(ConversationParticipant(conversation_id=conv.id, user_id=doctor.id, joined_at=utcnow()))
    db.session.commit()
    return conv


def get_or_create_private_conversation(user_a_id, user_b_id):
    a_convs = {i.conversation_id for i in ConversationParticipant.query.filter_by(user_id=user_a_id).all()}
    if a_convs:
        b_candidates = ConversationParticipant.query.filter(
            ConversationParticipant.user_id == user_b_id,
            ConversationParticipant.conversation_id.in_(list(a_convs)),
        ).all()
        for b in b_candidates:
            conv = db.session.get(Conversation, b.conversation_id)
            if conv and conv.type == "private" and ConversationParticipant.query.filter_by(conversation_id=conv.id).count() == 2:
                return conv

    ua = db.session.get(User, user_a_id)
    ub = db.session.get(User, user_b_id)
    conv = Conversation(type="private", name=f"{ua.display_name} / {ub.display_name}", created_by_user_id=user_a_id, updated_at=utcnow())
    db.session.add(conv)
    db.session.flush()
    db.session.add(ConversationParticipant(conversation_id=conv.id, user_id=user_a_id, joined_at=utcnow()))
    db.session.add(ConversationParticipant(conversation_id=conv.id, user_id=user_b_id, joined_at=utcnow()))
    db.session.commit()
    return conv


def check_conversation_member(conversation_id, user_id):
    return ConversationParticipant.query.filter_by(conversation_id=conversation_id, user_id=user_id).first() is not None


def gather_system_status():
    remote_status = "offline"
    remote_message = "连接失败"
    remote_metrics = {}
    try:
        # sample 服务对 /metrics 暴露健康状态
        response = requests.get(build_remote_url("/metrics"), timeout=5)
        if response.ok:
            remote_status = "online"
            remote_message = "连接正常"
            try:
                payload = response.json() if response.content else {}
                if isinstance(payload, dict):
                    remote_metrics = payload
            except Exception:
                remote_metrics = {}
        else:
            remote_message = f"HTTP {response.status_code}"
    except Exception as exc:
        # Fallback 到根路径探活，避免 /metrics 不存在时误判
        try:
            fallback = requests.get(str(app.config.get("REMOTE_INFER_BASE") or "").rstrip("/"), timeout=5)
            if fallback.ok:
                remote_status = "online"
                remote_message = "连接正常（根路径）"
            else:
                remote_message = str(exc)
        except Exception:
            remote_message = str(exc)

    queue_length = InferenceJob.query.filter(InferenceJob.status.in_(["queued", "running"])).count()
    recent = InferenceJob.query.order_by(InferenceJob.id.desc()).limit(50).all()
    success = [i for i in recent if i.status == "success" and i.latency_ms is not None]
    failed = [i for i in recent if i.status == "failed"]

    avg_latency = round(sum(i.latency_ms for i in success) / len(success), 2) if success else None
    error_rate = round((len(failed) / len(recent)) * 100, 2) if recent else 0.0

    cpu_percent = to_float(remote_metrics.get("cpu_percent"), None)
    ram_total_mb = to_float(remote_metrics.get("ram_total_mb"), None)
    ram_used_mb = to_float(remote_metrics.get("ram_used_mb"), None)
    ram_percent = to_float(remote_metrics.get("ram_percent"), None)
    gpu_mem_allocated_mb = to_float(remote_metrics.get("gpu_mem_allocated_mb"), None)
    gpu_mem_reserved_mb = to_float(remote_metrics.get("gpu_mem_reserved_mb"), None)
    process_rss_mb = to_float(remote_metrics.get("process_rss_mb"), None)
    metrics_ts = to_float(remote_metrics.get("ts"), None)

    if ram_percent is None and ram_total_mb and ram_used_mb is not None and ram_total_mb > 0:
        ram_percent = round((ram_used_mb / ram_total_mb) * 100, 2)

    infer_format = {
        "success_keys": [
            "status",
            "score",
            "cobb_deg",
            "curvature_deg",
            "curvature_per_seg",
            "vertebrae",
            "spine_midpoints",
            "coords",
            "image_base64",
            "image_mimetype",
            "_pelvic_tilt_metric",
            "_extra_models",
        ],
        "error_example": {"status": "error", "message": "image_base64 missing"},
    }

    return {
        "inference_server": {
            "status": remote_status,
            "message": remote_message,
            "queue_length": queue_length,
            "recent_latency_ms": avg_latency,
            "error_rate": error_rate,
            "recent_errors": [
                {"id": i.id, "exam_id": i.exam_id, "error": i.error_message, "finished_at": iso(i.finished_at)}
                for i in failed[:5]
            ],
            "metrics": {
                "cpu_percent": cpu_percent,
                "ram_total_mb": ram_total_mb,
                "ram_used_mb": ram_used_mb,
                "ram_percent": ram_percent,
                "gpu_mem_allocated_mb": gpu_mem_allocated_mb,
                "gpu_mem_reserved_mb": gpu_mem_reserved_mb,
                "process_rss_mb": process_rss_mb,
                "cuda_available": bool(remote_metrics.get("cuda_available", False)),
                "gpu_count": int(remote_metrics.get("gpu_count", 0) or 0),
                "ts": metrics_ts,
            },
            "infer_response_format": infer_format,
        },
        "database": {
            "status": "online",
            "patients": Patient.query.count(),
            "exams": Exam.query.count(),
            "messages": Message.query.count(),
        },
    }


def bootstrap_admin():
    if User.query.count() > 0:
        return
    user = User(
        username=os.getenv("SPINE_ADMIN_USER", "admin"),
        display_name="系统管理员",
        role="admin",
        is_active=True,
        module_permissions=json_dumps(DEFAULT_MODULES),
    )
    user.set_password(os.getenv("SPINE_ADMIN_PASSWORD", "admin123"))
    db.session.add(user)
    db.session.commit()


def serialize_exam_detail(exam):
    inference = json_loads(exam.inference_json, {}) or {}
    cervical_metric = inference.get("_cervical_metric") if isinstance(inference, dict) else None
    link = ExamShareLink.query.filter_by(exam_id=exam.id, is_active=True).first()
    share = None
    if link:
        share_url = url_for("public_case_page", token=link.token, _external=True)
        share = {
            "id": link.id,
            "token": link.token,
            "url": share_url,
            "qr_data_url": make_qr_data_url(share_url),
            "channel": f"share:{link.id}",
        }

    return {
        "id": exam.id,
        "patient_id": exam.patient_id,
        "patient_name": patient_display_name(exam.patient) if exam.patient else "-",
        "image_url": url_for("static", filename=(exam.inference_image_path or exam.image_path)),
        "raw_image_url": url_for("static", filename=exam.image_path),
        "inference_image_url": url_for("static", filename=exam.inference_image_path) if exam.inference_image_path else None,
        "status": exam.status,
        "uploaded_by_kind": exam.uploaded_by_kind,
        "uploaded_by_label": exam.uploaded_by_label,
        "created_at": iso(exam.created_at),
        "cobb_angle": exam.cobb_angle,
        "curve_value": exam.curve_value,
        "severity_label": exam.severity_label,
        "improvement_value": exam.improvement_value,
        "review_note": exam.review_note,
        "spine_class": exam.spine_class,
        "spine_class_text": spine_class_text(exam.spine_class),
        "spine_class_confidence": exam.spine_class_confidence,
        "cervical_metric": cervical_metric if isinstance(cervical_metric, dict) else None,
        "inference": inference,
        "share_link": share,
        "comment_channel": f"case_exam:{exam.id}",
    }


def serialize_questionnaire(item):
    return {
        "id": item.id,
        "title": item.title,
        "description": item.description,
        "status": item.status,
        "allow_non_patient": bool(item.allow_non_patient),
        "open_from": iso(item.open_from),
        "open_until": iso(item.open_until),
        "created_at": iso(item.created_at),
        "updated_at": iso(item.updated_at),
        "response_count": QuestionnaireResponse.query.filter_by(questionnaire_id=item.id).count(),
        "assignment_count": QuestionnaireAssignment.query.filter_by(questionnaire_id=item.id).count(),
    }


@app.route("/")
def page_root():
    return render_template("app_shell.html")


@app.route("/register/<token>")
def public_register_page(token):
    if not RegistrationSession.query.filter_by(token=token).first():
        abort(404)
    return render_template("public_register.html", token=token)


@app.route("/portal/<token>")
def public_portal_page(token):
    patient = Patient.query.filter_by(portal_token=token).first()
    if not patient:
        abort(404)
    resp = make_response(render_template("public_portal.html", token=token))
    cookie_max_age = 60 * 60 * 24 * 30
    resp.set_cookie("spine_patient_token", token, max_age=cookie_max_age, samesite="Lax", path="/")
    resp.set_cookie("spine_patient_id", str(patient.id), max_age=cookie_max_age, samesite="Lax", path="/")
    return resp


@app.route("/case/<token>")
def public_case_page(token):
    link = ExamShareLink.query.filter_by(token=token, is_active=True).first()
    if not link:
        abort(404)
    log_share_access(link, request)
    return render_template("public_case.html", token=token)


@app.route("/q/<token>")
def public_questionnaire_page(token):
    if not QuestionnaireAssignment.query.filter_by(token=token).first():
        abort(404)
    return render_template("public_questionnaire.html", token=token)


@app.route("/api/auth/session", methods=["GET"])
def api_auth_session():
    user = g.current_user
    if not user:
        return api_ok({"authenticated": False})
    return api_ok({"authenticated": True, "user": user.serialize(), "modules": user.modules()})


@app.route("/api/auth/login", methods=["POST"])
def api_auth_login():
    data = request.get_json(silent=True) or {}
    username = (data.get("username") or "").strip()
    password = data.get("password") or ""
    if not username or not password:
        return api_error("请输入账号和密码")

    user = User.query.filter(func.lower(User.username) == username.lower()).first()
    if not user or not user.check_password(password):
        return api_error("账号或密码错误", status=401, code="login_failed")
    if not user.is_active:
        return api_error("账号已被禁用", status=403, code="disabled")

    session.clear()
    session.permanent = True
    session["uid"] = user.id
    user.last_login_at = utcnow()
    db.session.commit()
    return api_ok({"user": user.serialize(), "modules": user.modules()}, message="登录成功")


@app.route("/api/auth/logout", methods=["POST"])
def api_auth_logout():
    session.clear()
    return api_ok(message="已退出")


@app.route("/api/overview", methods=["GET"])
@login_required_api
def api_overview():
    if not module_allowed("overview"):
        return api_error("无权限访问该模块", status=403, code="forbidden")

    unread_total = 0
    for part in ConversationParticipant.query.filter_by(user_id=g.current_user.id).all():
        unread_total += compute_unread_for_participant(part)

    today_start = datetime.combine(date.today(), datetime.min.time())
    tomorrow = today_start + timedelta(days=1)

    stats = {
        "patient_total": Patient.query.count(),
        "pending_reviews": Exam.query.filter_by(status="pending_review").count(),
        "unread_messages": unread_total,
        "today_schedules": FollowUpSchedule.query.filter(
            FollowUpSchedule.scheduled_at >= today_start,
            FollowUpSchedule.scheduled_at < tomorrow,
            FollowUpSchedule.status == "todo",
        ).count(),
        "alerts": Exam.query.filter(or_(Exam.severity_label == "重度", Exam.cobb_angle >= app.config["ALERT_COBB"])).count(),
    }

    system_status = gather_system_status()
    stats["inference_server"] = system_status["inference_server"]["status"]

    feed = WorkEvent.query.order_by(WorkEvent.created_at.desc()).limit(60).all()
    schedules = (
        FollowUpSchedule.query.filter(FollowUpSchedule.status == "todo")
        .order_by(FollowUpSchedule.scheduled_at.asc())
        .limit(50)
        .all()
    )

    return api_ok(
        {
            "stats": stats,
            "feed": [serialize_event(i) for i in feed],
            "schedules": [serialize_schedule(i) for i in schedules],
        }
    )


@app.route("/api/logs", methods=["GET"])
@login_required_api
def api_logs():
    try:
        limit = min(max(int(request.args.get("limit", "120")), 20), 500)
    except ValueError:
        limit = 120

    # 非管理员需要按归属过滤（复核相关日志仅对负责医生可见）。
    fetch_limit = min(limit * 5, 2000)
    rows = WorkEvent.query.order_by(WorkEvent.created_at.desc(), WorkEvent.id.desc()).limit(fetch_limit).all()

    items = []
    for row in rows:
        exam = db.session.get(Exam, row.exam_id) if row.exam_id else None
        patient = db.session.get(Patient, row.patient_id) if row.patient_id else None
        if g.current_user.role != "admin":
            if exam:
                if not can_user_access_exam_review(g.current_user, exam):
                    continue
            elif patient:
                if patient.created_by_user_id != g.current_user.id:
                    continue
            else:
                continue

        ref = json_loads(row.ref_json, {}) or {}
        pic_name = ref.get("pic_name") or (Path(exam.image_path).name if exam and exam.image_path else "")
        preview_path = exam.inference_image_path if exam and exam.inference_image_path else (exam.image_path if exam else None)
        preview_url = url_for("static", filename=preview_path) if preview_path else None
        items.append(
            {
                "id": row.id,
                "event_type": row.event_type,
                "title": row.title,
                "message": row.message,
                "level": row.level,
                "patient_id": row.patient_id,
                "exam_id": row.exam_id,
                "created_at": iso(row.created_at),
                "uploader_name": ref.get("uploader_name"),
                "owner_name": ref.get("owner_name"),
                "pic_name": pic_name,
                "preview_url": preview_url,
                "spine_class_text": ref.get("spine_class_text"),
                "confidence": ref.get("confidence"),
            }
        )
        if len(items) >= limit:
            break
    return api_ok({"items": items})


@app.route("/api/schedules", methods=["POST"])
@login_required_api
def api_create_schedule():
    data = request.get_json(silent=True) or {}
    patient_id = data.get("patient_id")
    title = (data.get("title") or "").strip()
    scheduled_at = parse_iso(data.get("scheduled_at"))
    if not patient_id or not title or not scheduled_at:
        return api_error("patient_id/title/scheduled_at 必填")

    patient = db.session.get(Patient, patient_id)
    if not patient:
        return api_error("患者不存在", status=404, code="not_found")

    row = FollowUpSchedule(
        patient_id=patient.id,
        title=title,
        note=(data.get("note") or "").strip() or None,
        scheduled_at=scheduled_at,
        status="todo",
        created_by_user_id=g.current_user.id,
    )
    db.session.add(row)
    db.session.commit()

    create_work_event("schedule", "新增随访日程", f"{patient_display_name(patient)}：{title}", patient_id=patient.id, ref={"schedule_id": row.id})
    return api_ok({"item": serialize_schedule(row)}, message="日程已创建")


@app.route("/api/patients", methods=["GET"])
@login_required_api
def api_patients_list():
    if not module_allowed("followup"):
        return api_error("无权限访问该模块", status=403, code="forbidden")

    page = max(int(request.args.get("page", "1")), 1)
    per_page = min(max(int(request.args.get("per_page", "20")), 1), 100)
    search = (request.args.get("search") or "").strip()

    unread_map = get_user_patient_unread_map(g.current_user.id)
    query = Patient.query
    if search:
        query = query.filter(Patient.name.ilike(f"%{search}%"))
    total = query.count()
    patients = query.order_by(Patient.updated_at.desc(), Patient.id.desc()).offset((page - 1) * per_page).limit(per_page).all()
    return api_ok({"items": [serialize_patient_row(i, unread_map) for i in patients], "total": total, "page": page, "per_page": per_page, "has_more": page * per_page < total})


@app.route("/api/patients", methods=["POST"])
@login_required_api
def api_patients_create():
    data = request.get_json(silent=True) or {}
    name = (data.get("name") or "").strip()
    if not name:
        return api_error("姓名必填")

    patient = Patient(
        name=name,
        age=data.get("age"),
        sex=(data.get("sex") or "").strip() or None,
        phone=(data.get("phone") or "").strip() or None,
        email=(data.get("email") or "").strip() or None,
        note=(data.get("note") or "").strip() or None,
        portal_token=generate_token("pt_"),
        created_by_user_id=g.current_user.id,
    )
    db.session.add(patient)
    db.session.commit()

    serialized = serialize_patient_row(patient, get_user_patient_unread_map(g.current_user.id))
    create_work_event("patient_created", "新增随访对象", f"{patient_display_name(patient)} 已建立档案", patient_id=patient.id, ref={"patient_id": patient.id})
    ws_broadcast("patients", {"type": "patient_created", "patient": serialized})
    return api_ok({"patient": serialized}, message="患者已创建")


@app.route("/api/patients/<int:patient_id>", methods=["DELETE"])
@login_required_api
def api_patients_delete(patient_id):
    if not module_allowed("followup"):
        return api_error("无权限访问该模块", status=403, code="forbidden")

    patient = db.session.get(Patient, patient_id)
    if not patient:
        return api_error("患者不存在", status=404, code="not_found")

    patient_name = patient_display_name(patient)
    exam_ids = [i.id for i in Exam.query.filter_by(patient_id=patient.id).all()]
    conversation_ids = [i.id for i in Conversation.query.filter_by(patient_id=patient.id).all()]

    if exam_ids:
        InferenceJob.query.filter(InferenceJob.exam_id.in_(exam_ids)).delete(synchronize_session=False)
        ExamShareLink.query.filter(ExamShareLink.exam_id.in_(exam_ids)).delete(synchronize_session=False)
        WorkEvent.query.filter(WorkEvent.exam_id.in_(exam_ids)).update({"exam_id": None}, synchronize_session=False)

    if conversation_ids:
        Message.query.filter(Message.conversation_id.in_(conversation_ids)).delete(synchronize_session=False)
        ConversationParticipant.query.filter(ConversationParticipant.conversation_id.in_(conversation_ids)).delete(synchronize_session=False)
        Conversation.query.filter(Conversation.id.in_(conversation_ids)).delete(synchronize_session=False)

    RegistrationSession.query.filter_by(patient_id=patient.id).update({"patient_id": None}, synchronize_session=False)
    WorkEvent.query.filter_by(patient_id=patient.id).update({"patient_id": None}, synchronize_session=False)
    FollowUpSchedule.query.filter_by(patient_id=patient.id).delete(synchronize_session=False)
    Exam.query.filter_by(patient_id=patient.id).delete(synchronize_session=False)

    db.session.delete(patient)
    db.session.commit()

    create_work_event("patient_deleted", "删除随访对象", f"{patient_name} 已删除", ref={"patient_id": patient_id})
    return api_ok(message="患者已删除")


@app.route("/api/patients/<int:patient_id>", methods=["PATCH"])
@login_required_api
def api_patients_update(patient_id):
    patient = db.session.get(Patient, patient_id)
    if not patient:
        return api_error("患者不存在", status=404, code="not_found")

    data = request.get_json(silent=True) or {}
    if "name" in data:
        name = (data.get("name") or "").strip()
        if not name:
            return api_error("姓名不能为空")
        patient.name = name

    for key in ["age", "sex", "phone", "email", "note"]:
        if key in data:
            value = data.get(key)
            if isinstance(value, str):
                value = value.strip() or None
            setattr(patient, key, value)

    db.session.commit()
    return api_ok({"patient": serialize_patient_row(patient, get_user_patient_unread_map(g.current_user.id))}, message="已保存")


@app.route("/api/patients/<int:patient_id>", methods=["GET"])
@login_required_api
def api_patient_detail(patient_id):
    patient = db.session.get(Patient, patient_id)
    if not patient:
        return api_error("患者不存在", status=404, code="not_found")

    exams = Exam.query.filter_by(patient_id=patient.id).order_by(Exam.created_at.asc(), Exam.id.asc()).all()
    timeline = (
        WorkEvent.query.filter(or_(WorkEvent.patient_id == patient.id, WorkEvent.exam_id.in_([e.id for e in exams] or [0])))
        .order_by(WorkEvent.created_at.desc())
        .limit(80)
        .all()
    )
    next_schedule = (
        FollowUpSchedule.query.filter(
            FollowUpSchedule.patient_id == patient.id,
            FollowUpSchedule.status == "todo",
            FollowUpSchedule.scheduled_at >= utcnow(),
        )
        .order_by(FollowUpSchedule.scheduled_at.asc())
        .first()
    )

    detail = serialize_patient_row(patient, get_user_patient_unread_map(g.current_user.id))
    detail.update(
        {
            "note": patient.note,
            "portal_token": patient.portal_token,
            "next_schedule": serialize_schedule(next_schedule) if next_schedule else None,
            "timeline": [serialize_event(i) for i in timeline],
            "trend": [{"date": iso(e.created_at), "cobb_angle": e.cobb_angle} for e in exams if e.cobb_angle is not None],
            "exams": [serialize_exam_row(e) for e in exams[::-1]],
        }
    )
    return api_ok({"patient": detail})


@app.route("/api/registration-sessions", methods=["POST"])
@login_required_api
def api_registration_create():
    data = request.get_json(silent=True) or {}
    init_state = data.get("form_state") if isinstance(data.get("form_state"), dict) else {}

    sess = RegistrationSession(
        token=generate_token("reg_"),
        created_by_user_id=g.current_user.id,
        form_state=json_dumps(init_state),
        status="active",
    )
    db.session.add(sess)
    db.session.commit()

    register_url = url_for("public_register_page", token=sess.token, _external=True)
    return api_ok(
        {
            "token": sess.token,
            "status": sess.status,
            "form_state": init_state,
            "register_url": register_url,
            "qr_data_url": make_qr_data_url(register_url),
            "channel": f"form:{sess.token}",
        },
        message="登记会话已创建",
    )


def _get_reg_session(token):
    return RegistrationSession.query.filter_by(token=token).first()


@app.route("/api/registration-sessions/<token>", methods=["GET"])
def api_registration_get(token):
    sess = _get_reg_session(token)
    if not sess:
        return api_error("登记会话不存在", status=404, code="not_found")
    patient = db.session.get(Patient, sess.patient_id) if sess.patient_id else None
    return api_ok(
        {
            "token": sess.token,
            "status": sess.status,
            "focus_field": sess.focus_field,
            "form_state": json_loads(sess.form_state, {}) or {},
            "patient": {
                "id": patient.id,
                "name": patient.name,
                "portal_token": patient.portal_token,
                "portal_url": url_for("public_portal_page", token=patient.portal_token, _external=True),
            }
            if patient
            else None,
            "updated_at": iso(sess.updated_at),
            "channel": f"form:{sess.token}",
        }
    )


@app.route("/api/registration-sessions/<token>/focus", methods=["POST"])
def api_registration_focus(token):
    sess = _get_reg_session(token)
    if not sess:
        return api_error("登记会话不存在", status=404, code="not_found")
    data = request.get_json(silent=True) or {}
    sess.focus_field = (data.get("field") or "").strip() or None
    db.session.commit()
    ws_broadcast(f"form:{token}", {"type": "field_focus", "field": sess.focus_field, "actor_name": data.get("actor_name") or "协作者", "ts": iso(utcnow())})
    return api_ok(message="ok")


@app.route("/api/registration-sessions/<token>/field", methods=["POST"])
def api_registration_field(token):
    sess = _get_reg_session(token)
    if not sess:
        return api_error("登记会话不存在", status=404, code="not_found")

    data = request.get_json(silent=True) or {}
    field = (data.get("field") or "").strip()
    if not field:
        return api_error("field 不能为空")

    state = json_loads(sess.form_state, {}) or {}
    state[field] = data.get("value")
    sess.form_state = json_dumps(state)
    db.session.commit()

    ws_broadcast(f"form:{token}", {"type": "field_change", "field": field, "value": data.get("value"), "actor_name": data.get("actor_name") or "协作者", "ts": iso(utcnow())})
    return api_ok(message="ok")


@app.route("/api/registration-sessions/<token>/submit", methods=["POST"])
def api_registration_submit(token):
    sess = _get_reg_session(token)
    if not sess:
        return api_error("登记会话不存在", status=404, code="not_found")

    data = request.get_json(silent=True) or {}
    actor = (data.get("actor_name") or "").strip() or "登记者"
    state = json_loads(sess.form_state, {}) or {}
    if isinstance(data.get("form_state"), dict):
        state.update(data["form_state"])

    name = (state.get("name") or "").strip()
    if not name:
        return api_error("姓名必填")

    patient = db.session.get(Patient, sess.patient_id) if sess.patient_id else None
    if not patient:
        patient = Patient(name=name, portal_token=generate_token("pt_"), created_by_user_id=sess.created_by_user_id)
        db.session.add(patient)
        db.session.flush()

    patient.name = name
    patient.age = int(state["age"]) if str(state.get("age") or "").isdigit() else None
    patient.sex = (state.get("sex") or "").strip() or None
    patient.phone = (state.get("phone") or "").strip() or None
    patient.email = (state.get("email") or "").strip() or None
    patient.note = (state.get("note") or "").strip() or None

    sess.patient_id = patient.id
    sess.status = "submitted"
    sess.form_state = json_dumps(state)
    db.session.commit()

    create_work_event("patient_registered", "新患者登记完成", f"{patient_display_name(patient)} 提交了登记信息", patient_id=patient.id, ref={"token": token})

    ws_broadcast(
        f"form:{token}",
        {
            "type": "form_submit",
            "actor_name": actor,
            "form_state": state,
            "patient": {"id": patient.id, "name": patient.name, "portal_url": url_for("public_portal_page", token=patient.portal_token, _external=True)},
            "ts": iso(utcnow()),
        },
    )

    patient_serialized = serialize_patient_row(patient, get_user_patient_unread_map(g.current_user.id) if g.current_user else {})
    ws_broadcast("patients", {"type": "patient_created", "patient": patient_serialized})

    return api_ok(
        {
            "patient": patient_serialized,
            "portal_token": patient.portal_token,
            "portal_url": url_for("public_portal_page", token=patient.portal_token, _external=True),
        },
        message="登记已提交",
    )


@app.route("/api/patients/<int:patient_id>/exams", methods=["POST"])
@login_required_api
def api_exam_upload_doctor(patient_id):
    patient = db.session.get(Patient, patient_id)
    if not patient:
        return api_error("患者不存在", status=404, code="not_found")

    file_obj = request.files.get("file")
    if not file_obj:
        return api_error("请选择影像文件")

    try:
        image_path = save_upload(file_obj)
    except ValueError as exc:
        return api_error(str(exc))

    exam = Exam(
        patient_id=patient.id,
        image_path=image_path,
        uploaded_by_kind="doctor",
        uploaded_by_user_id=g.current_user.id,
        uploaded_by_label=g.current_user.display_name,
        review_owner_user_id=g.current_user.id,
        status="pending_review",
    )
    db.session.add(exam)
    db.session.commit()

    run_remote_inference(exam)
    pic_name = Path(exam.image_path).name if exam.image_path else "影像"
    owner_name = review_owner_name(exam)
    create_work_event(
        "review_queue_add",
        "影像进入复核队列",
        f"{g.current_user.display_name} 上传的 {pic_name} 已加入 {owner_name} 的复核队列",
        patient_id=patient.id,
        exam_id=exam.id,
        level="warn",
        ref={"exam_id": exam.id, "pic_name": pic_name, "owner_name": owner_name, "uploader_name": g.current_user.display_name},
    )
    create_work_event("xray_upload", "新影像待复核", f"{patient_display_name(patient)} 上传了新的X光", patient_id=patient.id, exam_id=exam.id, level="warn", ref={"exam_id": exam.id, "pic_name": pic_name, "owner_name": owner_name})

    return api_ok({"exam": serialize_exam_row(exam)}, message="影像已上传")


@app.route("/api/reviews", methods=["GET"])
@login_required_api
def api_reviews():
    if not module_allowed("review"):
        return api_error("无权限访问该模块", status=403, code="forbidden")

    status = (request.args.get("status") or "pending_review").strip()
    page = max(int(request.args.get("page", "1")), 1)
    per_page = min(max(int(request.args.get("per_page", "20")), 1), 100)

    query = Exam.query
    if g.current_user.role != "admin":
        query = query.join(Patient, Patient.id == Exam.patient_id).filter(
            or_(Exam.review_owner_user_id == g.current_user.id, and_(Exam.review_owner_user_id.is_(None), Patient.created_by_user_id == g.current_user.id))
        )
    if status != "all":
        query = query.filter(Exam.status == status)
    total = query.count()
    items = query.order_by(Exam.created_at.desc(), Exam.id.desc()).offset((page - 1) * per_page).limit(per_page).all()
    return api_ok({"items": [serialize_exam_row(i) for i in items], "total": total, "page": page, "per_page": per_page, "has_more": page * per_page < total})


@app.route("/api/reviews/<int:exam_id>", methods=["GET"])
@login_required_api
def api_review_detail(exam_id):
    exam = db.session.get(Exam, exam_id)
    if not exam:
        return api_error("检查不存在", status=404, code="not_found")
    if not can_user_access_exam_review(g.current_user, exam):
        return api_error("无权限访问该复核记录", status=403, code="forbidden")
    comments = ExamComment.query.filter_by(exam_id=exam.id).order_by(ExamComment.created_at.asc()).all()
    detail = serialize_exam_detail(exam)
    detail["comments"] = [serialize_comment(c) for c in comments]
    return api_ok({"exam": detail})


@app.route("/api/reviews/<int:exam_id>/review", methods=["POST"])
@login_required_api
def api_review_submit(exam_id):
    exam = db.session.get(Exam, exam_id)
    if not exam:
        return api_error("检查不存在", status=404, code="not_found")
    if not can_user_access_exam_review(g.current_user, exam):
        return api_error("无权限提交该复核记录", status=403, code="forbidden")

    data = request.get_json(silent=True) or {}
    exam.status = "reviewed" if (data.get("decision") or "reviewed") == "reviewed" else "pending_review"
    exam.review_note = (data.get("note") or "").strip() or None
    exam.reviewed_by_user_id = g.current_user.id
    exam.reviewed_at = utcnow()
    db.session.commit()

    create_work_event("review_done", "影像复核完成", f"{patient_display_name(exam.patient)} 的影像已复核", patient_id=exam.patient_id, exam_id=exam.id)
    return api_ok({"exam": serialize_exam_detail(exam)}, message="复核结果已保存")


@app.route("/api/reviews/<int:exam_id>", methods=["DELETE"])
@login_required_api
def api_review_delete(exam_id):
    exam = db.session.get(Exam, exam_id)
    if not exam:
        return api_error("检查不存在", status=404, code="not_found")
    if not can_user_access_exam_review(g.current_user, exam):
        return api_error("无权限删除该复核记录", status=403, code="forbidden")

    patient = exam.patient
    patient_name = patient_display_name(patient) if patient else "患者"
    pic_name = Path(exam.image_path).name if exam.image_path else "影像"
    owner_name = review_owner_name(exam)
    image_path = exam.image_path
    inference_image_path = exam.inference_image_path

    share_link_ids = [i.id for i in ExamShareLink.query.filter_by(exam_id=exam.id).all()]
    if share_link_ids:
        ShareAccessLog.query.filter(ShareAccessLog.share_link_id.in_(share_link_ids)).delete(synchronize_session=False)
    ExamShareLink.query.filter_by(exam_id=exam.id).delete(synchronize_session=False)
    CaseShareToUser.query.filter_by(exam_id=exam.id).delete(synchronize_session=False)
    InferenceJob.query.filter_by(exam_id=exam.id).delete(synchronize_session=False)
    ExamComment.query.filter_by(exam_id=exam.id).delete(synchronize_session=False)
    WorkEvent.query.filter_by(exam_id=exam.id).update({"exam_id": None}, synchronize_session=False)

    db.session.delete(exam)
    db.session.commit()

    if image_path:
        try:
            file_path = BASE_DIR / "static" / image_path
            if file_path.exists():
                file_path.unlink()
        except Exception:
            pass

    if inference_image_path:
        try:
            file_path = BASE_DIR / "static" / inference_image_path
            if file_path.exists():
                file_path.unlink()
        except Exception:
            pass

    create_work_event(
        "review_deleted",
        "复核记录已删除",
        f"{patient_name} 的 {pic_name} 已从 {owner_name} 的复核队列删除",
        level="warn",
        patient_id=patient.id if patient else None,
        ref={
            "deleted_exam_id": exam_id,
            "pic_name": pic_name,
            "owner_name": owner_name,
            "deleted_by": g.current_user.display_name,
        },
    )
    return api_ok(message="复核记录已删除")


@app.route("/api/reviews/<int:exam_id>/share-link", methods=["POST"])
@login_required_api
def api_review_share_link(exam_id):
    exam = db.session.get(Exam, exam_id)
    if not exam:
        return api_error("检查不存在", status=404, code="not_found")
    if not can_user_access_exam_review(g.current_user, exam):
        return api_error("无权限分享该复核记录", status=403, code="forbidden")

    link = ensure_share_link(exam.id, g.current_user.id)
    share_url = url_for("public_case_page", token=link.token, _external=True)
    logs = ShareAccessLog.query.filter_by(share_link_id=link.id).order_by(ShareAccessLog.accessed_at.desc()).limit(50).all()

    create_work_event("case_shared", "病例链接已创建", f"{patient_display_name(exam.patient)} 的影像可分享讨论", patient_id=exam.patient_id, exam_id=exam.id, ref={"share_token": link.token})

    return api_ok(
        {
            "link": {
                "id": link.id,
                "token": link.token,
                "url": share_url,
                "qr_data_url": make_qr_data_url(share_url),
                "channel": f"share:{link.id}",
            },
            "accesses": [
                {
                    "id": i.id,
                    "access_ip": i.access_ip,
                    "viewer_label": i.viewer_label,
                    "user_agent": (i.user_agent or "")[:120],
                    "accessed_at": iso(i.accessed_at),
                }
                for i in logs
            ],
        },
        message="分享链接已就绪",
    )


@app.route("/api/reviews/<int:exam_id>/share-accesses", methods=["GET"])
@login_required_api
def api_review_share_accesses(exam_id):
    link = ExamShareLink.query.filter_by(exam_id=exam_id, is_active=True).first()
    if not link:
        return api_ok({"items": []})
    exam = db.session.get(Exam, exam_id)
    if not can_user_access_exam_review(g.current_user, exam):
        return api_error("无权限访问分享记录", status=403, code="forbidden")
    logs = ShareAccessLog.query.filter_by(share_link_id=link.id).order_by(ShareAccessLog.accessed_at.desc()).limit(80).all()
    return api_ok(
        {
            "items": [
                {
                    "id": i.id,
                    "access_ip": i.access_ip,
                    "viewer_label": i.viewer_label,
                    "user_agent": (i.user_agent or "")[:120],
                    "accessed_at": iso(i.accessed_at),
                }
                for i in logs
            ],
            "channel": f"share:{link.id}",
        }
    )


@app.route("/api/reviews/<int:exam_id>/comments", methods=["GET"])
@login_required_api
def api_review_comments(exam_id):
    exam = db.session.get(Exam, exam_id)
    if not exam:
        return api_error("检查不存在", status=404, code="not_found")
    if not can_user_access_exam_review(g.current_user, exam):
        return api_error("无权限访问评论", status=403, code="forbidden")
    rows = ExamComment.query.filter_by(exam_id=exam_id).order_by(ExamComment.created_at.asc()).all()
    return api_ok({"items": [serialize_comment(i) for i in rows], "channel": f"case_exam:{exam_id}"})


@app.route("/api/reviews/<int:exam_id>/comments", methods=["POST"])
@login_required_api
def api_review_comment_add(exam_id):
    exam = db.session.get(Exam, exam_id)
    if not exam:
        return api_error("检查不存在", status=404, code="not_found")
    if not can_user_access_exam_review(g.current_user, exam):
        return api_error("无权限评论该记录", status=403, code="forbidden")
    data = request.get_json(silent=True) or {}
    content = (data.get("content") or "").strip()
    if not content:
        return api_error("评论不能为空")

    row = ExamComment(exam_id=exam.id, author_kind="user", author_user_id=g.current_user.id, author_name=g.current_user.display_name, content=content)
    db.session.add(row)
    db.session.commit()
    payload = serialize_comment(row)
    ws_broadcast(f"case_exam:{exam.id}", {"type": "case_comment", "comment": payload})
    return api_ok({"comment": payload}, message="评论已发送")


@app.route("/api/reviews/<int:exam_id>/share-user", methods=["POST"])
@login_required_api
def api_review_share_user(exam_id):
    exam = db.session.get(Exam, exam_id)
    if not exam:
        return api_error("检查不存在", status=404, code="not_found")
    if not can_user_access_exam_review(g.current_user, exam):
        return api_error("无权限分享该记录", status=403, code="forbidden")
    data = request.get_json(silent=True) or {}
    target = db.session.get(User, data.get("user_id"))
    if not target or not target.is_active:
        return api_error("目标用户不存在", status=404, code="not_found")
    if target.id == g.current_user.id:
        return api_error("不能分享给自己")

    link = ensure_share_link(exam.id, g.current_user.id)
    share_url = url_for("public_case_page", token=link.token, _external=True)
    conv = get_or_create_private_conversation(g.current_user.id, target.id)

    db.session.add(CaseShareToUser(exam_id=exam.id, from_user_id=g.current_user.id, to_user_id=target.id))
    msg = Message(
        conversation_id=conv.id,
        sender_kind="user",
        sender_user_id=g.current_user.id,
        sender_name=g.current_user.display_name,
        message_type="share_case",
        content=f"分享病例：{patient_display_name(exam.patient)}",
        payload_json=json_dumps({"exam_id": exam.id, "share_url": share_url, "patient_id": exam.patient_id, "patient_name": patient_display_name(exam.patient)}),
    )
    conv.updated_at = utcnow()
    db.session.add(msg)
    db.session.commit()

    create_work_event("case_shared_user", "病例已分享给同事", f"{g.current_user.display_name} -> {target.display_name}", patient_id=exam.patient_id, exam_id=exam.id, ref={"conversation_id": conv.id, "to_user_id": target.id})
    ws_broadcast(f"chat:{conv.id}", {"type": "chat_message", "conversation_id": conv.id, "message": serialize_message(msg)})
    return api_ok({"conversation_id": conv.id}, message="已分享")


@app.route("/api/users/share-targets", methods=["GET"])
@login_required_api
def api_share_targets():
    keyword = (request.args.get("query") or "").strip().lower()
    users = User.query.filter(User.is_active.is_(True), User.id != g.current_user.id).all()

    current_conv_ids = {i.conversation_id for i in ConversationParticipant.query.filter_by(user_id=g.current_user.id).all()}
    result = []
    for user in users:
        if keyword and keyword not in user.display_name.lower() and keyword not in user.username.lower():
            continue

        score = datetime(1970, 1, 1)
        share = (
            CaseShareToUser.query.filter(
                or_(
                    and_(CaseShareToUser.from_user_id == g.current_user.id, CaseShareToUser.to_user_id == user.id),
                    and_(CaseShareToUser.from_user_id == user.id, CaseShareToUser.to_user_id == g.current_user.id),
                )
            )
            .order_by(CaseShareToUser.created_at.desc())
            .first()
        )
        if share and share.created_at > score:
            score = share.created_at

        target_conv_ids = {i.conversation_id for i in ConversationParticipant.query.filter_by(user_id=user.id).all()}
        common = list(current_conv_ids & target_conv_ids)
        if common:
            last_msg = Message.query.filter(Message.conversation_id.in_(common)).order_by(Message.created_at.desc()).first()
            if last_msg and last_msg.created_at > score:
                score = last_msg.created_at

        result.append({"id": user.id, "username": user.username, "display_name": user.display_name, "role": user.role, "last_interaction": iso(score) if score.year > 1970 else None, "_score": score})

    result.sort(key=lambda x: x["_score"], reverse=True)
    for row in result:
        row.pop("_score", None)
    return api_ok({"items": result})


@app.route("/api/public/case/<token>", methods=["GET"])
def api_public_case_data(token):
    link = ExamShareLink.query.filter_by(token=token, is_active=True).first()
    if not link:
        return api_error("链接不存在", status=404, code="not_found")
    exam = db.session.get(Exam, link.exam_id)
    if not exam:
        return api_error("检查不存在", status=404, code="not_found")
    rows = ExamComment.query.filter_by(exam_id=exam.id).order_by(ExamComment.created_at.asc()).all()
    detail = serialize_exam_detail(exam)
    detail["comments"] = [serialize_comment(i) for i in rows]
    return api_ok({"exam": detail})


@app.route("/api/public/case/<token>/comments", methods=["POST"])
def api_public_case_comment_add(token):
    link = ExamShareLink.query.filter_by(token=token, is_active=True).first()
    if not link:
        return api_error("链接不存在", status=404, code="not_found")
    exam = db.session.get(Exam, link.exam_id)
    if not exam:
        return api_error("检查不存在", status=404, code="not_found")

    data = request.get_json(silent=True) or {}
    content = (data.get("content") or "").strip()
    author_name = (data.get("author_name") or "访客").strip() or "访客"
    if not content:
        return api_error("评论不能为空")

    row = ExamComment(exam_id=exam.id, author_kind="guest", author_name=author_name, content=content)
    db.session.add(row)
    db.session.commit()

    payload = serialize_comment(row)
    ws_broadcast(f"case_exam:{exam.id}", {"type": "case_comment", "comment": payload})
    return api_ok({"comment": payload}, message="评论已发送")


@app.route("/api/chat/users", methods=["GET"])
@login_required_api
def api_chat_users():
    keyword = (request.args.get("query") or "").strip().lower()
    users = User.query.filter(User.is_active.is_(True), User.id != g.current_user.id).order_by(User.display_name.asc()).all()
    items = []
    for user in users:
        if keyword and keyword not in user.display_name.lower() and keyword not in user.username.lower():
            continue
        items.append({"id": user.id, "display_name": user.display_name, "username": user.username, "role": user.role})
    return api_ok({"items": items})


@app.route("/api/chat/conversations", methods=["GET"])
@login_required_api
def api_chat_conversations():
    if not module_allowed("chat"):
        return api_error("无权限访问该模块", status=403, code="forbidden")

    page = max(int(request.args.get("page", "1")), 1)
    per_page = min(max(int(request.args.get("per_page", "20")), 1), 100)

    conv_ids = [i.conversation_id for i in ConversationParticipant.query.filter_by(user_id=g.current_user.id).all()]
    if not conv_ids:
        return api_ok({"items": [], "total": 0, "page": 1, "per_page": per_page, "has_more": False})

    query = Conversation.query.filter(Conversation.id.in_(conv_ids)).order_by(Conversation.updated_at.desc(), Conversation.id.desc())
    total = query.count()
    conversations = query.offset((page - 1) * per_page).limit(per_page).all()
    items = [serialize_conversation(i, g.current_user.id) for i in conversations]
    items.sort(key=lambda x: x["updated_at"] or "", reverse=True)
    return api_ok({"items": items, "total": total, "page": page, "per_page": per_page, "has_more": page * per_page < total})


@app.route("/api/chat/conversations", methods=["POST"])
@login_required_api
def api_chat_conversation_create():
    data = request.get_json(silent=True) or {}
    ctype = (data.get("type") or "private").strip()

    if ctype == "private":
        target_id = data.get("target_user_id")
        target = db.session.get(User, target_id)
        if not target or not target.is_active:
            return api_error("目标用户不存在", status=404, code="not_found")
        conv = get_or_create_private_conversation(g.current_user.id, target.id)
        return api_ok({"conversation": serialize_conversation(conv, g.current_user.id)})

    if ctype == "group":
        name = (data.get("name") or "").strip()
        member_ids = data.get("member_user_ids") if isinstance(data.get("member_user_ids"), list) else []
        if not name:
            return api_error("群名称必填")

        all_ids = {g.current_user.id}
        for item in member_ids:
            try:
                all_ids.add(int(item))
            except (TypeError, ValueError):
                continue

        users = User.query.filter(User.id.in_(list(all_ids)), User.is_active.is_(True)).all()
        if len(users) < 2:
            return api_error("群成员至少2人")

        conv = Conversation(type="group", name=name, created_by_user_id=g.current_user.id, updated_at=utcnow())
        db.session.add(conv)
        db.session.flush()
        for user in users:
            db.session.add(ConversationParticipant(conversation_id=conv.id, user_id=user.id, joined_at=utcnow()))
        db.session.commit()
        return api_ok({"conversation": serialize_conversation(conv, g.current_user.id)}, message="群聊已创建")

    if ctype == "patient":
        patient = db.session.get(Patient, data.get("patient_id"))
        if not patient:
            return api_error("患者不存在", status=404, code="not_found")
        conv = get_or_create_patient_conversation(patient)
        return api_ok({"conversation": serialize_conversation(conv, g.current_user.id)})

    return api_error("不支持的会话类型")


@app.route("/api/chat/conversations/<int:conversation_id>/messages", methods=["GET"])
@login_required_api
def api_chat_messages(conversation_id):
    if not check_conversation_member(conversation_id, g.current_user.id):
        return api_error("无权限访问该会话", status=403, code="forbidden")

    try:
        limit = min(max(int(request.args.get("limit", "50")), 1), 300)
    except ValueError:
        limit = 50
    before_id = request.args.get("before_id")

    query = Message.query.filter_by(conversation_id=conversation_id)
    if before_id:
        try:
            query = query.filter(Message.id < int(before_id))
        except (ValueError, TypeError):
            pass
    rows = query.order_by(Message.id.desc()).limit(limit).all()
    rows.reverse()
    has_more = len(rows) == limit
    return api_ok({"items": [serialize_message(i) for i in rows], "channel": f"chat:{conversation_id}", "has_more": has_more})

@app.route("/api/chat/conversations/<int:conversation_id>/messages", methods=["POST"])
@login_required_api
def api_chat_message_send(conversation_id):
    if not check_conversation_member(conversation_id, g.current_user.id):
        return api_error("无权限访问该会话", status=403, code="forbidden")

    data = request.get_json(silent=True) or {}
    content = (data.get("content") or "").strip()
    mtype = (data.get("message_type") or "text").strip()
    payload = data.get("payload") if isinstance(data.get("payload"), dict) else {}

    if not content and mtype == "text":
        return api_error("消息不能为空")

    conv = db.session.get(Conversation, conversation_id)
    if not conv:
        return api_error("会话不存在", status=404, code="not_found")

    row = Message(
        conversation_id=conversation_id,
        sender_kind="user",
        sender_user_id=g.current_user.id,
        sender_name=g.current_user.display_name,
        message_type=mtype,
        content=content or f"[{mtype}]",
        payload_json=json_dumps(payload),
    )
    conv.updated_at = utcnow()
    db.session.add(row)
    db.session.commit()

    ws_broadcast(f"chat:{conversation_id}", {"type": "chat_message", "conversation_id": conversation_id, "message": serialize_message(row)})
    return api_ok({"message": serialize_message(row)}, message="发送成功")


@app.route("/api/chat/conversations/<int:conversation_id>/read", methods=["POST"])
@login_required_api
def api_chat_read(conversation_id):
    part = ConversationParticipant.query.filter_by(conversation_id=conversation_id, user_id=g.current_user.id).first()
    if not part:
        return api_error("无权限访问该会话", status=403, code="forbidden")
    latest = Message.query.filter_by(conversation_id=conversation_id).order_by(Message.id.desc()).first()
    part.last_read_message_id = latest.id if latest else part.last_read_message_id
    db.session.commit()
    return api_ok(message="已标记已读")


def active_questions_query(questionnaire_id):
    return Question.query.filter_by(questionnaire_id=questionnaire_id).filter(Question.is_active.is_(True))


def build_questionnaire_stats(questionnaire_id, questions):
    stats = []
    for question in questions:
        dist = {}
        total = 0
        answers = QuestionnaireAnswer.query.filter_by(question_id=question.id).all()
        for answer in answers:
            value = json_loads(answer.answer_json, None)
            if question.q_type == "multi" and isinstance(value, list):
                for opt in value:
                    key = str(opt)
                    dist[key] = dist.get(key, 0) + 1
                    total += 1
            else:
                key = str(value)
                dist[key] = dist.get(key, 0) + 1
                total += 1
        stats.append({"question_id": question.id, "title": question.title, "q_type": question.q_type, "distribution": dist, "total": total})
    return stats


@app.route("/api/questionnaires", methods=["GET"])
@login_required_api
def api_questionnaires():
    if not module_allowed("questionnaire"):
        return api_error("无权限访问该模块", status=403, code="forbidden")
    rows = Questionnaire.query.order_by(Questionnaire.created_at.desc(), Questionnaire.id.desc()).all()
    return api_ok({"items": [serialize_questionnaire(i) for i in rows]})


@app.route("/api/questionnaires", methods=["POST"])
@login_required_api
def api_questionnaire_create():
    data = request.get_json(silent=True) or {}
    title = (data.get("title") or "").strip()
    description = (data.get("description") or "").strip() or None
    allow_non_patient = to_bool(data.get("allow_non_patient"), False)
    open_from = parse_iso((data.get("open_from") or "").strip())
    open_until = parse_iso((data.get("open_until") or "").strip())
    questions = data.get("questions") if isinstance(data.get("questions"), list) else []

    if not title:
        return api_error("问卷标题必填")
    if not questions:
        return api_error("至少添加一个题目")

    if open_from and open_until and open_from > open_until:
        return api_error("开放时间范围无效")

    q = Questionnaire(
        title=title,
        description=description,
        status="active",
        allow_non_patient=allow_non_patient,
        open_from=open_from,
        open_until=open_until,
        created_by_user_id=g.current_user.id,
    )
    db.session.add(q)
    db.session.flush()

    for idx, item in enumerate(questions):
        try:
            q_type, q_title, options = normalize_question_payload(item)
        except ValueError as err:
            db.session.rollback()
            return api_error(str(err))
        db.session.add(Question(questionnaire_id=q.id, sort_order=idx, q_type=q_type, title=q_title, options_json=json_dumps(options)))

    db.session.commit()
    create_work_event("questionnaire_created", "新问卷已发布", q.title, ref={"questionnaire_id": q.id})
    return api_ok({"questionnaire": serialize_questionnaire(q)}, message="问卷已创建")


@app.route("/api/questionnaires/<int:qid>", methods=["GET"])
@login_required_api
def api_questionnaire_detail(qid):
    q = db.session.get(Questionnaire, qid)
    if not q:
        return api_error("问卷不存在", status=404, code="not_found")
    payload = serialize_questionnaire(q)
    questions = active_questions_query(q.id).order_by(Question.sort_order.asc(), Question.id.asc()).all()
    payload["questions"] = [serialize_question(i) for i in questions]
    payload["stats"] = build_questionnaire_stats(q.id, questions)
    payload["completed_count"] = QuestionnaireAssignment.query.filter_by(questionnaire_id=q.id, status="completed").count()
    payload["pending_count"] = QuestionnaireAssignment.query.filter_by(questionnaire_id=q.id, status="pending").count()
    return api_ok({"questionnaire": payload})


@app.route("/api/questionnaires/<int:qid>", methods=["PUT"])
@login_required_api
def api_questionnaire_update(qid):
    q = db.session.get(Questionnaire, qid)
    if not q:
        return api_error("问卷不存在", status=404, code="not_found")
    data = request.get_json(silent=True) or {}
    title = (data.get("title") or "").strip()
    description = (data.get("description") or "").strip() or None
    allow_non_patient = to_bool(data.get("allow_non_patient"), bool(q.allow_non_patient))
    open_from = parse_iso((data.get("open_from") or "").strip())
    open_until = parse_iso((data.get("open_until") or "").strip())
    questions = data.get("questions") if isinstance(data.get("questions"), list) else []
    if not title:
        return api_error("问卷标题必填")
    if not questions:
        return api_error("至少保留一个题目")
    if open_from and open_until and open_from > open_until:
        return api_error("开放时间范围无效")
    if QuestionnaireResponse.query.filter_by(questionnaire_id=q.id).count() > 0:
        return api_error("该问卷已有回收记录，请使用安全编辑接口")

    q.title = title
    q.description = description
    q.allow_non_patient = allow_non_patient
    q.open_from = open_from
    q.open_until = open_until
    Question.query.filter_by(questionnaire_id=q.id).delete()
    db.session.flush()
    for idx, item in enumerate(questions):
        try:
            q_type, q_title, options = normalize_question_payload(item)
        except ValueError as err:
            db.session.rollback()
            return api_error(str(err))
        db.session.add(Question(questionnaire_id=q.id, sort_order=idx, q_type=q_type, title=q_title, options_json=json_dumps(options)))
    db.session.commit()
    return api_ok({"questionnaire": serialize_questionnaire(q)}, message="问卷已更新")


@app.route("/api/questionnaires/<int:qid>/safe-edit", methods=["PATCH"])
@login_required_api
def api_questionnaire_safe_edit(qid):
    q = db.session.get(Questionnaire, qid)
    if not q:
        return api_error("问卷不存在", status=404, code="not_found")

    data = request.get_json(silent=True) or {}
    title = (data.get("title") or "").strip()
    description = (data.get("description") or "").strip() or None
    allow_non_patient = to_bool(data.get("allow_non_patient"), bool(q.allow_non_patient))
    open_from = parse_iso((data.get("open_from") or "").strip()) if data.get("open_from") is not None else q.open_from
    open_until = parse_iso((data.get("open_until") or "").strip()) if data.get("open_until") is not None else q.open_until
    questions_payload = data.get("questions") if isinstance(data.get("questions"), list) else []

    if not title:
        return api_error("问卷标题必填")
    if open_from and open_until and open_from > open_until:
        return api_error("开放时间范围无效")

    current_questions = active_questions_query(q.id).order_by(Question.sort_order.asc(), Question.id.asc()).all()
    current_map = {row.id: row for row in current_questions}

    kept_ids = []
    normalized_rows = []
    for idx, item in enumerate(questions_payload):
        qid_raw = item.get("id")
        try:
            question_id = int(qid_raw)
        except (TypeError, ValueError):
            return api_error("不允许新增题目，仅可修改或删除已有题目")
        row = current_map.get(question_id)
        if not row:
            return api_error("题目不存在或已删除，无法保存")
        try:
            q_type, q_title, options = normalize_question_payload(item)
        except ValueError as err:
            return api_error(str(err))
        if q_type != row.q_type:
            has_answers = QuestionnaireAnswer.query.filter_by(question_id=row.id).count() > 0
            if has_answers:
                return api_error(f"第 {idx + 1} 题已收集回答，不允许修改题型")
            row.q_type = q_type
        normalized_rows.append((idx, row, q_title, options))
        kept_ids.append(row.id)

    if not kept_ids:
        return api_error("至少保留一个题目")

    for idx, row, q_title, options in normalized_rows:
        row.sort_order = idx
        row.title = q_title
        row.options_json = json_dumps(options)
        row.is_active = True

    for row in current_questions:
        if row.id not in kept_ids:
            row.is_active = False

    q.title = title
    q.description = description
    q.allow_non_patient = allow_non_patient
    q.open_from = open_from
    q.open_until = open_until
    db.session.commit()
    return api_ok(message="问卷已保存")


@app.route("/api/questionnaires/<int:qid>", methods=["DELETE"])
@login_required_api
def api_questionnaire_delete(qid):
    q = db.session.get(Questionnaire, qid)
    if not q:
        return api_error("问卷不存在", status=404, code="not_found")
    title = q.title
    # Cascade delete related records
    response_ids = [r.id for r in QuestionnaireResponse.query.filter_by(questionnaire_id=qid).all()]
    if response_ids:
        QuestionnaireAnswer.query.filter(QuestionnaireAnswer.response_id.in_(response_ids)).delete(synchronize_session=False)
    QuestionnaireResponse.query.filter_by(questionnaire_id=qid).delete(synchronize_session=False)
    QuestionnaireAssignment.query.filter_by(questionnaire_id=qid).delete(synchronize_session=False)
    Question.query.filter_by(questionnaire_id=qid).delete(synchronize_session=False)
    db.session.delete(q)
    db.session.commit()
    return api_ok(message=f"问卷“{title}”已删除")


@app.route("/api/questionnaires/<int:qid>/stop", methods=["POST"])
@login_required_api
def api_questionnaire_stop(qid):
    q = db.session.get(Questionnaire, qid)
    if not q:
        return api_error("问卷不存在", status=404, code="not_found")
    q.status = "stopped"
    db.session.commit()
    return api_ok(message="问卷已终止")


@app.route("/api/questionnaires/<int:qid>/assign", methods=["POST"])
@login_required_api
def api_questionnaire_assign(qid):
    q = db.session.get(Questionnaire, qid)
    if not q:
        return api_error("问卷不存在", status=404, code="not_found")
    if q.status != "active":
        return api_error("问卷已终止，无法发送")

    data = request.get_json(silent=True) or {}
    patient_ids = data.get("patient_ids") if isinstance(data.get("patient_ids"), list) else []
    if not patient_ids:
        return api_error("请选择患者")

    created = []
    chat_messages_to_push = []
    for raw_id in patient_ids:
        try:
            pid = int(raw_id)
        except (TypeError, ValueError):
            continue
        patient = db.session.get(Patient, pid)
        if not patient:
            continue
        already_done = QuestionnaireResponse.query.filter_by(questionnaire_id=q.id, responder_patient_id=pid).count() > 0
        if already_done:
            continue

        existing = QuestionnaireAssignment.query.filter_by(questionnaire_id=q.id, patient_id=pid, status="pending").first()
        if existing:
            row = existing
            created.append(row)
        else:
            row = QuestionnaireAssignment(
                questionnaire_id=q.id,
                patient_id=pid,
                token=generate_token("qa_"),
                status="pending",
                sent_by_user_id=g.current_user.id,
                sent_at=utcnow(),
            )
            db.session.add(row)
            db.session.flush()
            created.append(row)
            create_work_event("questionnaire_sent", "问卷任务已发送", f"{patient_display_name(patient)} <- {q.title}", patient_id=pid, ref={"questionnaire_id": q.id, "assignment_id": row.id})

        try:
            conv = get_or_create_patient_conversation(patient)
            share_url = url_for("public_questionnaire_page", token=row.token, _external=True)
            msg = Message(
                conversation_id=conv.id,
                sender_kind="user",
                sender_user_id=g.current_user.id,
                sender_name=g.current_user.display_name,
                message_type="questionnaire_share",
                content=f"问卷：{q.title}",
                payload_json=json_dumps(
                    {
                        "questionnaire_id": q.id,
                        "assignment_id": row.id,
                        "questionnaire_title": q.title,
                        "share_url": share_url,
                    }
                ),
            )
            conv.updated_at = utcnow()
            db.session.add(msg)
            db.session.flush()
            chat_messages_to_push.append((conv.id, msg.id))
        except Exception:
            # 不影响问卷发送主流程
            pass

    db.session.commit()

    for conv_id, msg_id in chat_messages_to_push:
        try:
            msg = db.session.get(Message, msg_id)
            if msg:
                ws_broadcast(f"chat:{conv_id}", {"type": "chat_message", "conversation_id": conv_id, "message": serialize_message(msg)})
        except Exception:
            pass

    return api_ok(
        {
            "assignments": [
                {
                    "id": i.id,
                    "patient_id": i.patient_id,
                    "patient_name": patient_display_name(db.session.get(Patient, i.patient_id)),
                    "token": i.token,
                    "url": url_for("public_questionnaire_page", token=i.token, _external=True),
                    "status": i.status,
                }
                for i in created
            ]
        },
        message=f"已发送 {len(created)} 份",
    )


@app.route("/api/questionnaires/<int:qid>/responses", methods=["GET"])
@login_required_api
def api_questionnaire_responses(qid):
    q = db.session.get(Questionnaire, qid)
    if not q:
        return api_error("问卷不存在", status=404, code="not_found")

    responses = QuestionnaireResponse.query.filter_by(questionnaire_id=q.id).order_by(QuestionnaireResponse.submitted_at.desc()).all()

    questions = active_questions_query(q.id).order_by(Question.sort_order.asc()).all()
    stats = build_questionnaire_stats(q.id, questions)

    response_rows = []
    for row in responses:
        patient_name = None
        if row.assignment_id:
            assignment = db.session.get(QuestionnaireAssignment, row.assignment_id)
            if assignment:
                patient_name = patient_display_name(db.session.get(Patient, assignment.patient_id))
        responder = row.responder_name or patient_name or row.responder_ip or "匿名"
        response_rows.append({"id": row.id, "responder": responder, "patient_name": patient_name, "submitted_at": iso(row.submitted_at), "assignment_id": row.assignment_id})

    return api_ok({"stats": stats, "responses": response_rows})


@app.route("/api/questionnaires/<int:qid>/responses/<int:rid>", methods=["GET"])
@login_required_api
def api_questionnaire_response_detail(qid, rid):
    row = db.session.get(QuestionnaireResponse, rid)
    if not row or row.questionnaire_id != qid:
        return api_error("填写记录不存在", status=404, code="not_found")

    answers = []
    for answer in QuestionnaireAnswer.query.filter_by(response_id=row.id).all():
        question = db.session.get(Question, answer.question_id)
        answers.append({"question_id": answer.question_id, "question_title": question.title if question else f"题目-{answer.question_id}", "q_type": question.q_type if question else "text", "answer": json_loads(answer.answer_json, None)})

    return api_ok({"response": {"id": row.id, "submitted_at": iso(row.submitted_at), "responder_name": row.responder_name, "responder_ip": row.responder_ip, "answers": answers}})


@app.route("/api/questionnaires/<int:qid>/responses/<int:rid>", methods=["DELETE"])
@login_required_api
def api_questionnaire_response_delete(qid, rid):
    row = db.session.get(QuestionnaireResponse, rid)
    if not row or row.questionnaire_id != qid:
        return api_error("填写记录不存在", status=404, code="not_found")

    assignment = db.session.get(QuestionnaireAssignment, row.assignment_id) if row.assignment_id else None
    QuestionnaireAnswer.query.filter_by(response_id=row.id).delete()
    db.session.delete(row)
    db.session.flush()

    if assignment:
        has_any = QuestionnaireResponse.query.filter_by(assignment_id=assignment.id).count() > 0
        assignment.status = "completed" if has_any else "pending"
        assignment.completed_at = utcnow() if has_any else None

    db.session.commit()
    return api_ok(message="填写记录已删除")


@app.route("/api/public/questionnaires/<token>", methods=["GET"])
def api_public_questionnaire_get(token):
    assignment = QuestionnaireAssignment.query.filter_by(token=token).first()
    if not assignment:
        return api_error("任务不存在", status=404, code="not_found")
    questionnaire = db.session.get(Questionnaire, assignment.questionnaire_id)
    if not questionnaire:
        return api_error("问卷不存在", status=404, code="not_found")
    now = utcnow()
    already_submitted = QuestionnaireResponse.query.filter_by(assignment_id=assignment.id).count() > 0
    open_ok = True
    if questionnaire.open_from and now < questionnaire.open_from:
        open_ok = False
    if questionnaire.open_until and now > questionnaire.open_until:
        open_ok = False

    return api_ok(
        {
            "assignment": {
                "id": assignment.id,
                "status": assignment.status,
                "patient_name": patient_display_name(db.session.get(Patient, assignment.patient_id)),
                "already_submitted": already_submitted,
            },
            "questionnaire": {
                "id": questionnaire.id,
                "title": questionnaire.title,
                "description": questionnaire.description,
                "status": questionnaire.status,
                "allow_non_patient": bool(questionnaire.allow_non_patient),
                "open_from": iso(questionnaire.open_from),
                "open_until": iso(questionnaire.open_until),
                "open_ok": open_ok,
                "questions": [serialize_question(i) for i in active_questions_query(questionnaire.id).order_by(Question.sort_order.asc()).all()],
            },
        }
    )


@app.route("/api/public/questionnaires/<token>/submit", methods=["POST"])
def api_public_questionnaire_submit(token):
    assignment = QuestionnaireAssignment.query.filter_by(token=token).first()
    if not assignment:
        return api_error("任务不存在", status=404, code="not_found")
    questionnaire = db.session.get(Questionnaire, assignment.questionnaire_id)
    if not questionnaire:
        return api_error("问卷不存在", status=404, code="not_found")
    if questionnaire.status != "active":
        return api_error("问卷已终止", status=400, code="stopped")
    now = utcnow()
    if questionnaire.open_from and now < questionnaire.open_from:
        return api_error("问卷尚未开放", status=400, code="not_open")
    if questionnaire.open_until and now > questionnaire.open_until:
        return api_error("问卷已过开放时间", status=400, code="closed")
    if QuestionnaireResponse.query.filter_by(assignment_id=assignment.id).count() > 0:
        return api_error("该问卷任务已提交，不能重复填写", status=400, code="duplicated")

    data = request.get_json(silent=True) or {}
    answers_map = data.get("answers") if isinstance(data.get("answers"), dict) else {}
    responder_cookie_id = (data.get("responder_cookie_id") or "").strip() or None
    patient_cookie_token = (data.get("patient_cookie_token") or request.cookies.get("spine_patient_token") or "").strip() or None
    patient_from_cookie = Patient.query.filter_by(portal_token=patient_cookie_token).first() if patient_cookie_token else None
    if patient_from_cookie and patient_from_cookie.id != assignment.patient_id and not questionnaire.allow_non_patient:
        return api_error("仅患者本人可填写该问卷", status=403, code="forbidden")
    responder_patient_id = patient_from_cookie.id if patient_from_cookie else assignment.patient_id
    if responder_patient_id and QuestionnaireResponse.query.filter_by(questionnaire_id=questionnaire.id, responder_patient_id=responder_patient_id).count() > 0:
        return api_error("该用户已提交过本问卷", status=400, code="duplicated")
    if responder_cookie_id and QuestionnaireResponse.query.filter_by(questionnaire_id=questionnaire.id, responder_cookie_id=responder_cookie_id).count() > 0:
        return api_error("当前设备已提交过本问卷", status=400, code="duplicated")

    responder_name = (data.get("responder_name") or "").strip() or patient_display_name(db.session.get(Patient, assignment.patient_id))

    row = QuestionnaireResponse(
        questionnaire_id=questionnaire.id,
        assignment_id=assignment.id,
        responder_patient_id=responder_patient_id,
        responder_name=responder_name,
        responder_cookie_id=responder_cookie_id,
        responder_ip=request.remote_addr,
        submitted_at=utcnow(),
    )
    db.session.add(row)
    db.session.flush()

    for question in active_questions_query(questionnaire.id).all():
        key = str(question.id)
        db.session.add(QuestionnaireAnswer(response_id=row.id, question_id=question.id, answer_json=json_dumps(answers_map.get(key))))

    assignment.status = "completed"
    assignment.completed_at = utcnow()
    db.session.commit()

    create_work_event("questionnaire_completed", "问卷填写完成", f"{patient_display_name(db.session.get(Patient, assignment.patient_id))} 完成问卷：{questionnaire.title}", patient_id=assignment.patient_id, ref={"questionnaire_id": questionnaire.id, "response_id": row.id})
    return api_ok(message="提交成功")


@app.route("/api/public/portal/<token>", methods=["GET"])
def api_public_portal_get(token):
    patient = Patient.query.filter_by(portal_token=token).first()
    if not patient:
        return api_error("患者不存在", status=404, code="not_found")
    rows = QuestionnaireAssignment.query.filter_by(patient_id=patient.id).order_by(QuestionnaireAssignment.sent_at.desc()).limit(20).all()
    exams = Exam.query.filter_by(patient_id=patient.id).order_by(Exam.created_at.desc(), Exam.id.desc()).limit(60).all()
    events = WorkEvent.query.filter_by(patient_id=patient.id).order_by(WorkEvent.created_at.desc(), WorkEvent.id.desc()).limit(80).all()
    needs_profile = not patient.age and not patient.sex and not patient.phone
    return api_ok(
        {
            "patient": {"id": patient.id, "name": patient_display_name(patient), "age": patient.age, "sex": patient.sex, "phone": patient.phone},
            "needs_profile": needs_profile,
            "uploads": [
                {
                    "id": i.id,
                    "upload_date": iso(i.created_at),
                    "status": i.status,
                    "spine_class": i.spine_class,
                    "spine_class_text": spine_class_text(i.spine_class),
                    "spine_class_confidence": i.spine_class_confidence,
                    "cobb_angle": i.cobb_angle,
                    "curve_value": i.curve_value,
                    "severity_label": i.severity_label,
                    "improvement_value": i.improvement_value,
                    "review_note": i.review_note,
                    "reviewed_at": iso(i.reviewed_at),
                    "uploaded_by_kind": i.uploaded_by_kind,
                    "uploaded_by_label": i.uploaded_by_label,
                    "image_url": url_for("static", filename=i.image_path) if i.image_path else None,
                    "raw_image_url": url_for("static", filename=i.image_path) if i.image_path else None,
                    "inference_image_url": url_for("static", filename=i.inference_image_path) if i.inference_image_path else None,
                    "can_delete": i.uploaded_by_kind == "patient" and i.status != "reviewed",
                    "cervical_avg_ratio": (lambda inf: inf.get("_cervical_metric", {}).get("avg_ratio") if isinstance(inf, dict) and isinstance(inf.get("_cervical_metric"), dict) else None)(json_loads(i.inference_json, {}) or {}),
                    "cervical_assessment": (lambda inf: inf.get("_cervical_metric", {}).get("assessment") if isinstance(inf, dict) and isinstance(inf.get("_cervical_metric"), dict) else None)(json_loads(i.inference_json, {}) or {}),
                }
                for i in exams
            ],
            "timeline": [serialize_event(i) for i in events],
            "assignments": [
                {
                    "id": i.id,
                    "status": i.status,
                    "sent_at": iso(i.sent_at),
                    "completed_at": iso(i.completed_at),
                    "questionnaire_title": db.session.get(Questionnaire, i.questionnaire_id).title if db.session.get(Questionnaire, i.questionnaire_id) else "问卷",
                    "url": url_for("public_questionnaire_page", token=i.token, _external=True),
                }
                for i in rows
            ],
        }
    )


@app.route("/api/public/portal/<token>/profile", methods=["POST"])
def api_public_portal_update_profile(token):
    patient = Patient.query.filter_by(portal_token=token).first()
    if not patient:
        return api_error("患者不存在", status=404, code="not_found")
    data = request.get_json(silent=True) or {}
    name = (data.get("name") or "").strip()
    if name:
        patient.name = name
    age_val = data.get("age")
    if str(age_val or "").strip().isdigit():
        patient.age = int(age_val)
    sex = (data.get("sex") or "").strip()
    if sex:
        patient.sex = sex
    phone = (data.get("phone") or "").strip()
    if phone:
        patient.phone = phone
    db.session.commit()
    return api_ok({"patient": {"id": patient.id, "name": patient_display_name(patient), "age": patient.age, "sex": patient.sex, "phone": patient.phone}}, message="信息已更新")


@app.route("/api/public/portal/<token>/chat", methods=["GET"])
def api_public_portal_chat(token):
    patient = Patient.query.filter_by(portal_token=token).first()
    if not patient:
        return api_error("患者不存在", status=404, code="not_found")

    conv = get_or_create_patient_conversation(patient)
    participants = ConversationParticipant.query.filter_by(conversation_id=conv.id).all()
    contacts = []
    for p in participants:
        user = db.session.get(User, p.user_id)
        if not user or not user.is_active:
            continue
        contacts.append(
            {
                "id": user.id,
                "name": user.display_name,
                "role": user.role,
            }
        )

    messages = Message.query.filter_by(conversation_id=conv.id).order_by(Message.id.asc()).limit(300).all()
    return api_ok(
        {
            "conversation": {
                "id": conv.id,
                "name": conversation_name(conv),
                "channel": f"chat:{conv.id}",
            },
            "contacts": contacts,
            "messages": [serialize_message(i) for i in messages],
            "patient_name": patient_display_name(patient),
        }
    )


@app.route("/api/public/portal/<token>/messages", methods=["POST"])
def api_public_portal_message(token):
    patient = Patient.query.filter_by(portal_token=token).first()
    if not patient:
        return api_error("患者不存在", status=404, code="not_found")

    data = request.get_json(silent=True) or {}
    content = (data.get("content") or "").strip()
    sender_name = (data.get("sender_name") or patient_display_name(patient)).strip() or patient_display_name(patient)
    if not content:
        return api_error("消息不能为空")

    conv = get_or_create_patient_conversation(patient)
    row = Message(conversation_id=conv.id, sender_kind="patient", sender_name=sender_name, content=content, message_type="text")
    conv.updated_at = utcnow()
    db.session.add(row)
    db.session.commit()

    create_work_event("message", "患者消息待处理", f"{patient_display_name(patient)} 发来新消息", patient_id=patient.id, ref={"conversation_id": conv.id})
    ws_broadcast(f"chat:{conv.id}", {"type": "chat_message", "conversation_id": conv.id, "message": serialize_message(row)})
    return api_ok({"message": serialize_message(row)}, message="发送成功")


@app.route("/api/public/portal/<token>/exams", methods=["POST"])
def api_public_portal_exam(token):
    patient = Patient.query.filter_by(portal_token=token).first()
    if not patient:
        return api_error("患者不存在", status=404, code="not_found")
    file_obj = request.files.get("file")
    if not file_obj:
        return api_error("请选择影像文件")

    try:
        image_path = save_upload(file_obj)
    except ValueError as exc:
        return api_error(str(exc))

    exam = Exam(
        patient_id=patient.id,
        image_path=image_path,
        uploaded_by_kind="patient",
        uploaded_by_label=(request.form.get("sender_name") or patient_display_name(patient)).strip() or patient_display_name(patient),
        review_owner_user_id=patient.created_by_user_id,
        status="pending_review",
    )
    db.session.add(exam)
    db.session.commit()

    run_remote_inference(exam)
    pic_name = Path(exam.image_path).name if exam.image_path else "影像"
    owner_name = review_owner_name(exam)
    uploader_name = exam.uploaded_by_label or patient_display_name(patient)
    create_work_event(
        "review_queue_add",
        "影像进入复核队列",
        f"{uploader_name} 上传的 {pic_name} 已加入 {owner_name} 的复核队列",
        patient_id=patient.id,
        exam_id=exam.id,
        level="warn",
        ref={"exam_id": exam.id, "pic_name": pic_name, "owner_name": owner_name, "uploader_name": uploader_name},
    )
    create_work_event(
        "xray_upload",
        "患者上传新影像",
        f"{patient_display_name(patient)} 上传了新的X光待复核",
        patient_id=patient.id,
        exam_id=exam.id,
        level="warn",
        ref={"exam_id": exam.id, "pic_name": pic_name, "owner_name": owner_name},
    )
    return api_ok({"exam": serialize_exam_row(exam)}, message="上传成功")


@app.route("/api/public/portal/<token>/exams/<int:exam_id>", methods=["DELETE"])
def api_public_portal_exam_delete(token, exam_id):
    patient = Patient.query.filter_by(portal_token=token).first()
    if not patient:
        return api_error("患者不存在", status=404, code="not_found")

    exam = db.session.get(Exam, exam_id)
    if not exam or exam.patient_id != patient.id:
        return api_error("影像不存在", status=404, code="not_found")
    if exam.uploaded_by_kind != "patient":
        return api_error("仅可删除患者本人上传的影像", status=403, code="forbidden")
    if exam.status == "reviewed":
        return api_error("该影像已复核，不能删除", status=403, code="forbidden")

    image_path = exam.image_path
    inference_image_path = exam.inference_image_path

    InferenceJob.query.filter_by(exam_id=exam.id).delete(synchronize_session=False)
    ExamShareLink.query.filter_by(exam_id=exam.id).delete(synchronize_session=False)
    WorkEvent.query.filter_by(exam_id=exam.id).delete(synchronize_session=False)

    db.session.delete(exam)
    db.session.commit()

    if image_path:
        try:
            file_path = BASE_DIR / "static" / image_path
            if file_path.exists():
                file_path.unlink()
        except Exception:
            pass

    if inference_image_path:
        try:
            file_path = BASE_DIR / "static" / inference_image_path
            if file_path.exists():
                file_path.unlink()
        except Exception:
            pass

    create_work_event("xray_deleted", "患者删除上传影像", f"{patient_display_name(patient)} 删除了一张影像", patient_id=patient.id, level="info")
    return api_ok(message="影像已删除")


@app.route("/api/system/status", methods=["GET"])
@login_required_api
def api_system_status():
    if not module_allowed("status"):
        return api_error("无权限访问该模块", status=403, code="forbidden")
    return api_ok(gather_system_status())


@app.route("/api/users", methods=["GET"])
@admin_required_api
def api_users():
    rows = User.query.order_by(User.created_at.desc(), User.id.desc()).all()
    return api_ok({"items": [i.serialize() for i in rows]})


@app.route("/api/users", methods=["POST"])
@admin_required_api
def api_user_create():
    data = request.get_json(silent=True) or {}
    username = (data.get("username") or "").strip()
    display_name = (data.get("display_name") or "").strip()
    password = data.get("password") or ""
    role = (data.get("role") or "doctor").strip()

    if not username or not display_name or not password:
        return api_error("username/display_name/password 必填")
    if len(password) < 6:
        return api_error("密码至少6位")
    if role not in ROLE_OPTIONS:
        return api_error("角色不合法")
    if User.query.filter(func.lower(User.username) == username.lower()).first():
        return api_error("用户名已存在")

    modules = data.get("module_permissions") if isinstance(data.get("module_permissions"), list) else module_defaults_for_role(role)
    row = User(username=username, display_name=display_name, role=role, is_active=True, module_permissions=json_dumps(modules))
    row.set_password(password)
    db.session.add(row)
    db.session.commit()
    return api_ok({"user": row.serialize()}, message="用户已创建")


@app.route("/api/users/<int:user_id>", methods=["PATCH"])
@admin_required_api
def api_user_update(user_id):
    row = db.session.get(User, user_id)
    if not row:
        return api_error("用户不存在", status=404, code="not_found")

    data = request.get_json(silent=True) or {}
    if "display_name" in data:
        display_name = (data.get("display_name") or "").strip()
        if not display_name:
            return api_error("display_name 不能为空")
        row.display_name = display_name

    if "role" in data:
        role = (data.get("role") or "").strip()
        if role not in ROLE_OPTIONS:
            return api_error("角色不合法")
        row.role = role

    if "is_active" in data:
        if row.id == g.current_user.id and not bool(data.get("is_active")):
            return api_error("不能禁用当前账号")
        row.is_active = bool(data.get("is_active"))

    if "module_permissions" in data and isinstance(data.get("module_permissions"), list):
        row.module_permissions = json_dumps(data.get("module_permissions"))

    pwd = data.get("password")
    if isinstance(pwd, str) and pwd:
        if len(pwd) < 6:
            return api_error("密码至少6位")
        row.set_password(pwd)

    db.session.commit()
    return api_ok({"user": row.serialize()}, message="用户已更新")


@app.route("/api/lookups/base", methods=["GET"])
@login_required_api
def api_lookups_base():
    users = User.query.filter(User.is_active.is_(True)).order_by(User.display_name.asc()).all()
    patients = Patient.query.order_by(Patient.updated_at.desc()).limit(300).all()
    unread_map = get_user_patient_unread_map(g.current_user.id)
    return api_ok(
        {
            "users": [{"id": u.id, "display_name": u.display_name, "username": u.username, "role": u.role} for u in users],
            "patients": [serialize_patient_row(p, unread_map) for p in patients],
        }
    )


@app.route("/healthz", methods=["GET"])
def healthz():
    return jsonify({"ok": True, "time": iso(utcnow())})


@app.route("/api/public/register/<token>", methods=["GET"])
def api_public_register_get(token):
    return api_registration_get(token)


@app.route("/api/public/register/<token>/focus", methods=["POST"])
def api_public_register_focus(token):
    return api_registration_focus(token)


@app.route("/api/public/register/<token>/field", methods=["POST"])
def api_public_register_field(token):
    return api_registration_field(token)


@app.route("/api/public/register/<token>/submit", methods=["POST"])
def api_public_register_submit(token):
    return api_registration_submit(token)


# ── Anonymous inference trial ──
@app.route("/api/public/try-inference", methods=["POST"])
def api_public_try_inference():
    file_obj = request.files.get("file")
    if not file_obj:
        return api_error("请选择影像文件")

    ext = Path(secure_filename(file_obj.filename or "upload.png")).suffix.lower()
    if ext not in ALLOWED_UPLOAD_EXT:
        return api_error("仅支持 png/jpg/jpeg/bmp/webp")

    image_bytes = file_obj.read()
    if not image_bytes:
        return api_error("文件为空")

    try:
        result = run_anonymous_inference(image_bytes)
    except Exception as exc:
        return api_error(f"推理失败：{str(exc)}", status=500, code="inference_error")
    return api_ok({"result": result}, message="推理完成")


# ── AI chat (anonymous) ──
@app.route("/api/public/ai-chat", methods=["POST"])
def api_public_ai_chat():
    data = request.get_json(silent=True) or {}
    user_message = (data.get("message") or "").strip()
    session_token = (data.get("session_token") or "").strip()
    inference_context = data.get("inference_context")

    if not user_message:
        return api_error("消息不能为空")

    ip = get_client_ip()

    if session_token:
        chat_session = AiChatSession.query.filter_by(session_token=session_token).first()
        if not chat_session:
            return api_error("会话不存在", status=404, code="not_found")
    else:
        chat_session = AiChatSession(
            session_token=secrets.token_urlsafe(32),
            ip_address=ip,
        )
        db.session.add(chat_session)
        db.session.commit()

    # Build message history
    history_rows = AiChatMessage.query.filter_by(session_id=chat_session.id).order_by(AiChatMessage.id).all()
    messages = [{"role": m.role, "content": m.content} for m in history_rows]
    messages.append({"role": "user", "content": user_message})

    # Resolve inference context: use provided, or first saved context
    ctx = inference_context
    if ctx is None:
        for m in history_rows:
            if m.inference_context:
                ctx = json_loads(m.inference_context, None)
                if ctx:
                    break

    try:
        assistant_reply = call_stepfun(messages, inference_context=ctx)
    except Exception as exc:
        return api_error(f"AI回复失败：{str(exc)}", status=500, code="llm_error")

    user_msg = AiChatMessage(
        session_id=chat_session.id,
        role="user",
        content=user_message,
        inference_context=json_dumps(inference_context) if inference_context else None,
    )
    assistant_msg = AiChatMessage(
        session_id=chat_session.id,
        role="assistant",
        content=assistant_reply,
    )
    db.session.add(user_msg)
    db.session.add(assistant_msg)
    db.session.commit()

    return api_ok({
        "session_token": chat_session.session_token,
        "reply": assistant_reply,
        "message_id": assistant_msg.id,
    })


@app.route("/api/public/ai-chat/<session_token>/messages", methods=["GET"])
def api_public_ai_chat_messages(session_token):
    chat_session = AiChatSession.query.filter_by(session_token=session_token).first()
    if not chat_session:
        return api_error("会话不存在", status=404, code="not_found")
    msgs = AiChatMessage.query.filter_by(session_id=chat_session.id).order_by(AiChatMessage.id).all()
    return api_ok({"messages": [
        {"id": m.id, "role": m.role, "content": m.content, "created_at": iso(m.created_at)}
        for m in msgs
    ]})


# ── AI chat SSE streaming (anonymous) ──
@app.route("/api/public/ai-chat/stream", methods=["POST"])
def api_public_ai_chat_stream():
    data = request.get_json(silent=True) or {}
    user_message = (data.get("message") or "").strip()
    session_token_in = (data.get("session_token") or "").strip()
    inference_context = data.get("inference_context")

    if not user_message:
        return api_error("消息不能为空")

    ip = get_client_ip()

    if session_token_in:
        chat_session = AiChatSession.query.filter_by(session_token=session_token_in).first()
        if not chat_session:
            return api_error("会话不存在", status=404, code="not_found")
    else:
        chat_session = AiChatSession(session_token=secrets.token_urlsafe(32), ip_address=ip)
        db.session.add(chat_session)
        db.session.commit()

    history_rows = AiChatMessage.query.filter_by(session_id=chat_session.id).order_by(AiChatMessage.id).all()
    messages = [{"role": m.role, "content": m.content} for m in history_rows]
    messages.append({"role": "user", "content": user_message})

    ctx = inference_context
    if ctx is None:
        for m in history_rows:
            if m.inference_context:
                ctx = json_loads(m.inference_context, None)
                if ctx:
                    break

    user_msg = AiChatMessage(
        session_id=chat_session.id, role="user", content=user_message,
        inference_context=json_dumps(inference_context) if inference_context else None,
    )
    db.session.add(user_msg)
    db.session.commit()

    session_id = chat_session.id
    out_token = chat_session.session_token

    def generate():
        full_parts = []
        try:
            for chunk in call_stepfun_stream(messages, inference_context=ctx):
                full_parts.append(chunk)
                yield f"data: {json.dumps({'delta': chunk}, ensure_ascii=False)}\n\n"
        except Exception as exc:
            yield f"data: {json.dumps({'error': str(exc)}, ensure_ascii=False)}\n\n"
            return
        full_reply = "".join(full_parts)
        with app.app_context():
            assistant_msg = AiChatMessage(session_id=session_id, role="assistant", content=full_reply)
            db.session.add(assistant_msg)
            db.session.commit()
            yield f"data: {json.dumps({'done': True, 'session_token': out_token, 'message_id': assistant_msg.id}, ensure_ascii=False)}\n\n"

    return Response(generate(), content_type="text/event-stream", headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


# ── AI chat SSE streaming (patient portal) ──
@app.route("/api/public/portal/<token>/ai-chat/stream", methods=["POST"])
def api_public_portal_ai_chat_stream(token):
    patient = Patient.query.filter_by(portal_token=token).first()
    if not patient:
        return api_error("患者不存在", status=404, code="not_found")

    data = request.get_json(silent=True) or {}
    user_message = (data.get("message") or "").strip()
    session_token_in = (data.get("session_token") or "").strip()
    inference_context = data.get("inference_context")

    if not user_message:
        return api_error("消息不能为空")

    if session_token_in:
        chat_session = AiChatSession.query.filter_by(session_token=session_token_in, patient_id=patient.id).first()
        if not chat_session:
            return api_error("会话不存在", status=404, code="not_found")
    else:
        chat_session = AiChatSession(session_token=secrets.token_urlsafe(32), patient_id=patient.id, ip_address=get_client_ip())
        db.session.add(chat_session)
        db.session.commit()

    history_rows = AiChatMessage.query.filter_by(session_id=chat_session.id).order_by(AiChatMessage.id).all()
    messages = [{"role": m.role, "content": m.content} for m in history_rows]
    messages.append({"role": "user", "content": user_message})

    ctx = inference_context
    if ctx is None:
        for m in history_rows:
            if m.inference_context:
                ctx = json_loads(m.inference_context, None)
                if ctx:
                    break
    if ctx is None:
        latest_exam = Exam.query.filter(Exam.patient_id == patient.id, Exam.inference_json.isnot(None)).order_by(Exam.created_at.desc()).first()
        if latest_exam:
            inf = json_loads(latest_exam.inference_json, {})
            ctx = {
                "spine_class": latest_exam.spine_class,
                "spine_class_text": spine_class_text(latest_exam.spine_class),
                "cobb_angle": latest_exam.cobb_angle,
                "severity_label": latest_exam.severity_label,
                "cervical_metric": inf.get("_cervical_metric") if isinstance(inf, dict) else None,
            }

    user_msg = AiChatMessage(
        session_id=chat_session.id, role="user", content=user_message,
        inference_context=json_dumps(inference_context) if inference_context else None,
    )
    db.session.add(user_msg)
    db.session.commit()

    session_id = chat_session.id
    out_token = chat_session.session_token

    def generate():
        full_parts = []
        try:
            for chunk in call_stepfun_stream(messages, inference_context=ctx):
                full_parts.append(chunk)
                yield f"data: {json.dumps({'delta': chunk}, ensure_ascii=False)}\n\n"
        except Exception as exc:
            yield f"data: {json.dumps({'error': str(exc)}, ensure_ascii=False)}\n\n"
            return
        full_reply = "".join(full_parts)
        with app.app_context():
            assistant_msg = AiChatMessage(session_id=session_id, role="assistant", content=full_reply)
            db.session.add(assistant_msg)
            db.session.commit()
            yield f"data: {json.dumps({'done': True, 'session_token': out_token, 'message_id': assistant_msg.id}, ensure_ascii=False)}\n\n"

    return Response(generate(), content_type="text/event-stream", headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


# ── AI chat (patient portal) ──
@app.route("/api/public/portal/<token>/ai-chat", methods=["POST"])
def api_public_portal_ai_chat(token):
    patient = Patient.query.filter_by(portal_token=token).first()
    if not patient:
        return api_error("患者不存在", status=404, code="not_found")

    data = request.get_json(silent=True) or {}
    user_message = (data.get("message") or "").strip()
    session_token = (data.get("session_token") or "").strip()
    inference_context = data.get("inference_context")

    if not user_message:
        return api_error("消息不能为空")

    if session_token:
        chat_session = AiChatSession.query.filter_by(session_token=session_token, patient_id=patient.id).first()
        if not chat_session:
            return api_error("会话不存在", status=404, code="not_found")
    else:
        chat_session = AiChatSession(
            session_token=secrets.token_urlsafe(32),
            patient_id=patient.id,
            ip_address=get_client_ip(),
        )
        db.session.add(chat_session)
        db.session.commit()

    history_rows = AiChatMessage.query.filter_by(session_id=chat_session.id).order_by(AiChatMessage.id).all()
    messages = [{"role": m.role, "content": m.content} for m in history_rows]
    messages.append({"role": "user", "content": user_message})

    # Auto-attach latest inference data if no explicit context
    ctx = inference_context
    if ctx is None:
        for m in history_rows:
            if m.inference_context:
                ctx = json_loads(m.inference_context, None)
                if ctx:
                    break
    if ctx is None:
        latest_exam = (
            Exam.query.filter(Exam.patient_id == patient.id, Exam.inference_json.isnot(None))
            .order_by(Exam.created_at.desc())
            .first()
        )
        if latest_exam:
            inf = json_loads(latest_exam.inference_json, {})
            ctx = {
                "spine_class": latest_exam.spine_class,
                "spine_class_text": spine_class_text(latest_exam.spine_class),
                "cobb_angle": latest_exam.cobb_angle,
                "severity_label": latest_exam.severity_label,
                "cervical_metric": inf.get("_cervical_metric") if isinstance(inf, dict) else None,
            }

    try:
        assistant_reply = call_stepfun(messages, inference_context=ctx)
    except Exception as exc:
        return api_error(f"AI回复失败：{str(exc)}", status=500, code="llm_error")

    user_msg = AiChatMessage(
        session_id=chat_session.id,
        role="user",
        content=user_message,
        inference_context=json_dumps(inference_context) if inference_context else None,
    )
    assistant_msg = AiChatMessage(
        session_id=chat_session.id,
        role="assistant",
        content=assistant_reply,
    )
    db.session.add(user_msg)
    db.session.add(assistant_msg)
    db.session.commit()

    return api_ok({
        "session_token": chat_session.session_token,
        "reply": assistant_reply,
        "message_id": assistant_msg.id,
    })


@app.route("/api/public/portal/<token>/ai-messages", methods=["GET"])
def api_public_portal_ai_messages(token):
    patient = Patient.query.filter_by(portal_token=token).first()
    if not patient:
        return api_error("患者不存在", status=404, code="not_found")

    session_token = request.args.get("session_token", "").strip()
    if session_token:
        chat_session = AiChatSession.query.filter_by(session_token=session_token, patient_id=patient.id).first()
        if not chat_session:
            return api_error("会话不存在", status=404, code="not_found")
        msgs = AiChatMessage.query.filter_by(session_id=chat_session.id).order_by(AiChatMessage.id).all()
    else:
        sessions = AiChatSession.query.filter_by(patient_id=patient.id).order_by(AiChatSession.created_at.desc()).all()
        if not sessions:
            return api_ok({"sessions": [], "messages": []})
        return api_ok({"sessions": [
            {"session_token": s.session_token, "created_at": iso(s.created_at), "message_count": AiChatMessage.query.filter_by(session_id=s.id).count()}
            for s in sessions
        ]})

    return api_ok({"messages": [
        {"id": m.id, "role": m.role, "content": m.content, "created_at": iso(m.created_at)}
        for m in msgs
    ]})


def ensure_schema_columns():
    rows = db.session.execute(text("PRAGMA table_info(wb_exams)")).mappings().all()
    columns = {str(r.get("name") or "") for r in rows}
    updated = False
    if "inference_image_path" not in columns:
        db.session.execute(text("ALTER TABLE wb_exams ADD COLUMN inference_image_path VARCHAR(256)"))
        updated = True
    if "review_owner_user_id" not in columns:
        db.session.execute(text("ALTER TABLE wb_exams ADD COLUMN review_owner_user_id INTEGER"))
        updated = True
    if "spine_class" not in columns:
        db.session.execute(text("ALTER TABLE wb_exams ADD COLUMN spine_class VARCHAR(24)"))
        updated = True
    if "spine_class_id" not in columns:
        db.session.execute(text("ALTER TABLE wb_exams ADD COLUMN spine_class_id INTEGER"))
        updated = True
    if "spine_class_confidence" not in columns:
        db.session.execute(text("ALTER TABLE wb_exams ADD COLUMN spine_class_confidence FLOAT"))
        updated = True

    q_rows = db.session.execute(text("PRAGMA table_info(wb_questionnaires)")).mappings().all()
    q_columns = {str(r.get("name") or "") for r in q_rows}
    if "allow_non_patient" not in q_columns:
        db.session.execute(text("ALTER TABLE wb_questionnaires ADD COLUMN allow_non_patient BOOLEAN DEFAULT 0"))
        updated = True
    if "open_from" not in q_columns:
        db.session.execute(text("ALTER TABLE wb_questionnaires ADD COLUMN open_from DATETIME"))
        updated = True
    if "open_until" not in q_columns:
        db.session.execute(text("ALTER TABLE wb_questionnaires ADD COLUMN open_until DATETIME"))
        updated = True

    qq_rows = db.session.execute(text("PRAGMA table_info(wb_questions)")).mappings().all()
    qq_columns = {str(r.get("name") or "") for r in qq_rows}
    if "is_active" not in qq_columns:
        db.session.execute(text("ALTER TABLE wb_questions ADD COLUMN is_active BOOLEAN DEFAULT 1"))
        updated = True
        db.session.execute(text("UPDATE wb_questions SET is_active = 1 WHERE is_active IS NULL"))

    qr_rows = db.session.execute(text("PRAGMA table_info(wb_questionnaire_responses)")).mappings().all()
    qr_columns = {str(r.get("name") or "") for r in qr_rows}
    if "responder_patient_id" not in qr_columns:
        db.session.execute(text("ALTER TABLE wb_questionnaire_responses ADD COLUMN responder_patient_id INTEGER"))
        updated = True
    if "responder_cookie_id" not in qr_columns:
        db.session.execute(text("ALTER TABLE wb_questionnaire_responses ADD COLUMN responder_cookie_id VARCHAR(128)"))
        updated = True
    if updated:
        db.session.commit()


with app.app_context():
    db.create_all()
    ensure_schema_columns()
    bootstrap_admin()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)

