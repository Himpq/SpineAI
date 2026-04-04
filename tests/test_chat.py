# -*- coding: utf-8 -*-
"""Tests for chat API endpoints."""

from tests.conftest import _login


def _create_conversation(auth_client, patient_id):
    """Helper to create a patient conversation."""
    resp = auth_client.post("/api/chat/conversations", json={
        "type": "patient",
        "patient_id": patient_id,
    })
    assert resp.status_code == 200
    return resp.get_json()["data"]["conversation"]


class TestChatConversations:
    """GET/POST /api/chat/conversations"""

    def test_unauthenticated(self, client):
        resp = client.get("/api/chat/conversations")
        assert resp.status_code == 401

    def test_empty_list(self, auth_client):
        resp = auth_client.get("/api/chat/conversations")
        data = resp.get_json()
        assert resp.status_code == 200
        assert data["data"]["items"] == []

    def test_create_patient_conversation(self, auth_client, sample_patient):
        conv = _create_conversation(auth_client, sample_patient["id"])
        assert conv["type"] == "patient"
        assert conv["id"] > 0

    def test_duplicate_patient_conversation(self, auth_client, sample_patient):
        """Creating conversation for same patient should return existing one."""
        c1 = _create_conversation(auth_client, sample_patient["id"])
        c2 = _create_conversation(auth_client, sample_patient["id"])
        assert c1["id"] == c2["id"]

    def test_list_after_create(self, auth_client, sample_patient):
        _create_conversation(auth_client, sample_patient["id"])
        resp = auth_client.get("/api/chat/conversations")
        items = resp.get_json()["data"]["items"]
        assert len(items) >= 1


class TestChatMessages:
    """GET/POST /api/chat/conversations/<cid>/messages"""

    def test_send_and_list(self, auth_client, sample_patient):
        conv = _create_conversation(auth_client, sample_patient["id"])
        cid = conv["id"]

        # Send message
        resp = auth_client.post(f"/api/chat/conversations/{cid}/messages", json={
            "content": "你好，患者",
        })
        assert resp.status_code == 200
        msg = resp.get_json()["data"]["message"]
        assert msg["content"] == "你好，患者"

        # List messages
        resp = auth_client.get(f"/api/chat/conversations/{cid}/messages")
        data = resp.get_json()["data"]
        assert len(data["items"]) >= 1

    def test_cursor_pagination(self, auth_client, sample_patient):
        conv = _create_conversation(auth_client, sample_patient["id"])
        cid = conv["id"]

        # Send 5 messages
        msg_ids = []
        for i in range(5):
            resp = auth_client.post(f"/api/chat/conversations/{cid}/messages", json={"content": f"消息{i}"})
            msg_ids.append(resp.get_json()["data"]["message"]["id"])

        # Get with limit
        resp = auth_client.get(f"/api/chat/conversations/{cid}/messages?limit=3")
        data = resp.get_json()["data"]
        assert len(data["items"]) == 3

        # Get older with before_id
        oldest_id = data["items"][0]["id"]
        resp = auth_client.get(f"/api/chat/conversations/{cid}/messages?before_id={oldest_id}&limit=10")
        data2 = resp.get_json()["data"]
        assert len(data2["items"]) >= 1
        # All messages should be older
        for m in data2["items"]:
            assert m["id"] < oldest_id


class TestChatRead:
    """POST /api/chat/conversations/<cid>/read"""

    def test_mark_read(self, auth_client, sample_patient):
        conv = _create_conversation(auth_client, sample_patient["id"])
        cid = conv["id"]
        resp = auth_client.post(f"/api/chat/conversations/{cid}/read")
        assert resp.status_code == 200
