# -*- coding: utf-8 -*-
"""Tests for questionnaire API endpoints."""


def _create_questionnaire(auth_client, title="测试问卷"):
    """Helper to create a questionnaire with one question."""
    resp = auth_client.post("/api/questionnaires", json={
        "title": title,
        "description": "测试用问卷",
        "questions": [
            {"title": "你的年龄？", "q_type": "text"},
            {"title": "性别", "q_type": "single", "options": ["男", "女"]},
        ],
    })
    assert resp.status_code == 200, f"Create failed: {resp.get_json()}"
    return resp.get_json()["data"]["questionnaire"]


class TestQuestionnaireList:
    """GET /api/questionnaires"""

    def test_unauthenticated(self, client):
        resp = client.get("/api/questionnaires")
        assert resp.status_code == 401

    def test_empty_list(self, auth_client):
        resp = auth_client.get("/api/questionnaires")
        data = resp.get_json()
        assert resp.status_code == 200
        assert data["data"]["items"] == []

    def test_list_after_create(self, auth_client):
        _create_questionnaire(auth_client)
        resp = auth_client.get("/api/questionnaires")
        items = resp.get_json()["data"]["items"]
        assert len(items) >= 1


class TestQuestionnaireCreate:
    """POST /api/questionnaires"""

    def test_success(self, auth_client):
        q = _create_questionnaire(auth_client)
        assert q["title"] == "测试问卷"
        assert q["status"] == "active"

    def test_title_required(self, auth_client):
        resp = auth_client.post("/api/questionnaires", json={
            "questions": [{"title": "Q1", "type": "text"}],
        })
        assert resp.status_code == 400

    def test_questions_required(self, auth_client):
        resp = auth_client.post("/api/questionnaires", json={
            "title": "空问卷",
        })
        assert resp.status_code == 400


class TestQuestionnaireDetail:
    """GET /api/questionnaires/<qid>"""

    def test_success(self, auth_client):
        q = _create_questionnaire(auth_client)
        resp = auth_client.get(f"/api/questionnaires/{q['id']}")
        data = resp.get_json()
        assert resp.status_code == 200
        assert "questions" in data["data"]["questionnaire"]

    def test_not_found(self, auth_client):
        resp = auth_client.get("/api/questionnaires/99999")
        assert resp.status_code == 404


class TestQuestionnaireDelete:
    """DELETE /api/questionnaires/<qid>"""

    def test_delete_success(self, auth_client):
        q = _create_questionnaire(auth_client)
        resp = auth_client.delete(f"/api/questionnaires/{q['id']}")
        assert resp.status_code == 200

    def test_delete_not_found(self, auth_client):
        resp = auth_client.delete("/api/questionnaires/99999")
        assert resp.status_code == 404


class TestQuestionnaireStop:
    """POST /api/questionnaires/<qid>/stop"""

    def test_stop(self, auth_client):
        q = _create_questionnaire(auth_client)
        resp = auth_client.post(f"/api/questionnaires/{q['id']}/stop")
        assert resp.status_code == 200
