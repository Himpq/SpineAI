# -*- coding: utf-8 -*-
"""Tests for authentication API endpoints."""

from tests.conftest import _login


class TestAuthSession:
    """GET /api/auth/session"""

    def test_unauthenticated(self, client):
        resp = client.get("/api/auth/session")
        data = resp.get_json()
        assert resp.status_code == 200
        assert data["data"]["authenticated"] is False

    def test_authenticated(self, auth_client):
        resp = auth_client.get("/api/auth/session")
        data = resp.get_json()
        assert resp.status_code == 200
        assert data["data"]["authenticated"] is True
        assert data["data"]["user"]["username"] == "admin"


class TestLogin:
    """POST /api/auth/login"""

    def test_success(self, client):
        resp = _login(client)
        data = resp.get_json()
        assert resp.status_code == 200
        assert data["ok"] is True
        assert data["data"]["user"]["username"] == "admin"

    def test_wrong_password(self, client):
        resp = _login(client, password="wrong")
        assert resp.status_code == 401

    def test_unknown_user(self, client):
        resp = _login(client, username="noone", password="x")
        assert resp.status_code == 401

    def test_missing_fields(self, client):
        resp = client.post("/api/auth/login", json={})
        assert resp.status_code in (400, 401)


class TestLogout:
    """POST /api/auth/logout"""

    def test_logout(self, auth_client):
        resp = auth_client.post("/api/auth/logout")
        assert resp.status_code == 200
        # After logout, session should be gone
        resp = auth_client.get("/api/auth/session")
        assert resp.get_json()["data"]["authenticated"] is False
