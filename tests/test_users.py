# -*- coding: utf-8 -*-
"""Tests for user management (admin) API endpoints."""

from tests.conftest import _login


class TestUsersList:
    """GET /api/users"""

    def test_unauthenticated(self, client):
        resp = client.get("/api/users")
        assert resp.status_code == 401

    def test_non_admin(self, doctor_client):
        resp = doctor_client.get("/api/users")
        assert resp.status_code == 403

    def test_admin_success(self, auth_client):
        resp = auth_client.get("/api/users")
        data = resp.get_json()
        assert resp.status_code == 200
        # Should contain at least the admin user
        assert len(data["data"]) >= 1


class TestUsersCreate:
    """POST /api/users"""

    def test_create_doctor(self, auth_client):
        resp = auth_client.post("/api/users", json={
            "username": "newdoc",
            "display_name": "新医生",
            "password": "pass123",
            "role": "doctor",
        })
        data = resp.get_json()
        assert resp.status_code == 200
        assert data["data"]["user"]["username"] == "newdoc"

    def test_duplicate_username(self, auth_client):
        auth_client.post("/api/users", json={
            "username": "dup",
            "display_name": "A",
            "password": "pass123",
            "role": "doctor",
        })
        resp = auth_client.post("/api/users", json={
            "username": "dup",
            "display_name": "B",
            "password": "pass123",
            "role": "doctor",
        })
        assert resp.status_code == 400

    def test_non_admin_forbidden(self, doctor_client):
        resp = doctor_client.post("/api/users", json={
            "username": "x",
            "display_name": "X",
            "password": "pass123",
            "role": "doctor",
        })
        assert resp.status_code == 403


class TestUsersUpdate:
    """PATCH /api/users/<id>"""

    def test_update_display_name(self, auth_client):
        # Create a user first
        resp = auth_client.post("/api/users", json={
            "username": "upuser",
            "display_name": "原名",
            "password": "pass123",
            "role": "doctor",
        })
        uid = resp.get_json()["data"]["user"]["id"]

        resp = auth_client.patch(f"/api/users/{uid}", json={"display_name": "新名"})
        assert resp.status_code == 200
        assert resp.get_json()["data"]["user"]["display_name"] == "新名"

    def test_toggle_active(self, auth_client):
        resp = auth_client.post("/api/users", json={
            "username": "toggleme",
            "display_name": "T",
            "password": "pass123",
            "role": "doctor",
        })
        uid = resp.get_json()["data"]["user"]["id"]

        resp = auth_client.patch(f"/api/users/{uid}", json={"is_active": False})
        assert resp.status_code == 200
        assert resp.get_json()["data"]["user"]["is_active"] is False
