# -*- coding: utf-8 -*-
"""Tests for overview and system API endpoints."""


class TestOverview:
    """GET /api/overview"""

    def test_unauthenticated(self, client):
        resp = client.get("/api/overview")
        assert resp.status_code == 401

    def test_success(self, auth_client):
        resp = auth_client.get("/api/overview")
        data = resp.get_json()
        assert resp.status_code == 200
        assert "stats" in data["data"]
        stats = data["data"]["stats"]
        assert "patient_total" in stats
        assert "pending_reviews" in stats
        assert "unread_messages" in stats

    def test_with_patient(self, auth_client, sample_patient):
        resp = auth_client.get("/api/overview")
        stats = resp.get_json()["data"]["stats"]
        assert stats["patient_total"] >= 1

    def test_feed_and_schedules(self, auth_client):
        resp = auth_client.get("/api/overview")
        data = resp.get_json()["data"]
        assert "feed" in data
        assert "schedules" in data
        assert isinstance(data["feed"], list)


class TestSystemStatus:
    """GET /api/system/status"""

    def test_unauthenticated(self, client):
        resp = client.get("/api/system/status")
        assert resp.status_code == 401

    def test_success(self, auth_client):
        resp = auth_client.get("/api/system/status")
        data = resp.get_json()
        assert resp.status_code == 200
        assert "data" in data


class TestHealthz:
    """GET /healthz"""

    def test_healthz(self, client):
        resp = client.get("/healthz")
        assert resp.status_code == 200


class TestLookups:
    """GET /api/lookups/base"""

    def test_unauthenticated(self, client):
        resp = client.get("/api/lookups/base")
        assert resp.status_code == 401

    def test_success(self, auth_client):
        resp = auth_client.get("/api/lookups/base")
        assert resp.status_code == 200
