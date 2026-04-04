# -*- coding: utf-8 -*-
"""Tests for patient CRUD API endpoints."""


class TestPatientList:
    """GET /api/patients"""

    def test_unauthenticated(self, client):
        resp = client.get("/api/patients")
        assert resp.status_code == 401

    def test_empty_list(self, auth_client):
        resp = auth_client.get("/api/patients")
        data = resp.get_json()
        assert resp.status_code == 200
        assert data["data"]["items"] == []
        assert data["data"]["total"] == 0

    def test_pagination(self, auth_client):
        # Create 3 patients
        for i in range(3):
            auth_client.post("/api/patients", json={"name": f"患者{i}"})

        # Page 1, per_page=2
        resp = auth_client.get("/api/patients?page=1&per_page=2")
        data = resp.get_json()["data"]
        assert len(data["items"]) == 2
        assert data["total"] == 3
        assert data["has_more"] is True

        # Page 2
        resp = auth_client.get("/api/patients?page=2&per_page=2")
        data = resp.get_json()["data"]
        assert len(data["items"]) == 1
        assert data["has_more"] is False

    def test_search(self, auth_client):
        auth_client.post("/api/patients", json={"name": "张三"})
        auth_client.post("/api/patients", json={"name": "李四"})

        resp = auth_client.get("/api/patients?search=张")
        data = resp.get_json()["data"]
        assert data["total"] == 1
        assert data["items"][0]["name"] == "张三"


class TestPatientCreate:
    """POST /api/patients"""

    def test_success(self, auth_client):
        resp = auth_client.post("/api/patients", json={
            "name": "新患者",
            "age": 30,
            "sex": "男",
            "phone": "13900139000",
        })
        data = resp.get_json()
        assert resp.status_code == 200
        assert data["ok"] is True
        assert data["data"]["patient"]["name"] == "新患者"
        assert data["data"]["patient"]["age"] == 30

    def test_name_required(self, auth_client):
        resp = auth_client.post("/api/patients", json={"age": 20})
        assert resp.status_code == 400

    def test_empty_name_rejected(self, auth_client):
        resp = auth_client.post("/api/patients", json={"name": "  "})
        assert resp.status_code == 400

    def test_unauthenticated(self, client):
        resp = client.post("/api/patients", json={"name": "X"})
        assert resp.status_code == 401


class TestPatientUpdate:
    """PATCH /api/patients/<id>"""

    def test_update_name(self, auth_client, sample_patient):
        pid = sample_patient["id"]
        resp = auth_client.patch(f"/api/patients/{pid}", json={"name": "改名"})
        data = resp.get_json()
        assert resp.status_code == 200
        assert data["data"]["patient"]["name"] == "改名"

    def test_update_multiple_fields(self, auth_client, sample_patient):
        pid = sample_patient["id"]
        resp = auth_client.patch(f"/api/patients/{pid}", json={
            "age": 40,
            "sex": "男",
            "phone": "13700137000",
            "note": "测试备注",
        })
        data = resp.get_json()["data"]["patient"]
        assert data["age"] == 40
        # note is not returned in the list serializer; verify via detail
        resp2 = auth_client.get(f"/api/patients/{pid}")
        patient_data = resp2.get_json()["data"]["patient"]
        assert patient_data["note"] == "测试备注"

    def test_empty_name_rejected(self, auth_client, sample_patient):
        pid = sample_patient["id"]
        resp = auth_client.patch(f"/api/patients/{pid}", json={"name": ""})
        assert resp.status_code == 400

    def test_not_found(self, auth_client):
        resp = auth_client.patch("/api/patients/99999", json={"name": "X"})
        assert resp.status_code == 404


class TestPatientDelete:
    """DELETE /api/patients/<id>"""

    def test_delete_success(self, auth_client, sample_patient):
        pid = sample_patient["id"]
        resp = auth_client.delete(f"/api/patients/{pid}")
        assert resp.status_code == 200

        # Verify gone
        resp = auth_client.get(f"/api/patients/{pid}")
        assert resp.status_code == 404

    def test_delete_not_found(self, auth_client):
        resp = auth_client.delete("/api/patients/99999")
        assert resp.status_code == 404

    def test_unauthenticated(self, client):
        resp = client.delete("/api/patients/1")
        assert resp.status_code == 401


class TestPatientDetail:
    """GET /api/patients/<id>"""

    def test_success(self, auth_client, sample_patient):
        pid = sample_patient["id"]
        resp = auth_client.get(f"/api/patients/{pid}")
        data = resp.get_json()
        assert resp.status_code == 200
        patient = data["data"]["patient"]
        assert patient["name"] == "测试患者"
        assert "exams" in patient
        assert "trend" in patient

    def test_not_found(self, auth_client):
        resp = auth_client.get("/api/patients/99999")
        assert resp.status_code == 404
