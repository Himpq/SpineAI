# -*- coding: utf-8 -*-
"""Tests for review API endpoints."""
import io

from unittest.mock import patch


def _create_exam(db_session, patient_id, status="pending_review"):
    """Helper to create an exam directly in DB (no real image upload)."""
    from app import Exam
    exam = Exam(
        patient_id=patient_id,
        image_path="uploads/test.png",
        status=status,
        uploaded_by_kind="doctor",
        uploaded_by_label="娴嬭瘯鍖荤敓",
        cobb_angle=25.5,
        curve_value=0.3,
        severity_label="涓害",
        spine_class="S-curve",
        spine_class_id=2,
    )
    db_session.add(exam)
    db_session.commit()
    return exam


class TestReviewList:
    """GET /api/reviews"""

    def test_unauthenticated(self, client):
        resp = client.get("/api/reviews")
        assert resp.status_code == 401

    def test_empty_list(self, auth_client):
        resp = auth_client.get("/api/reviews")
        data = resp.get_json()
        assert resp.status_code == 200
        assert data["data"]["items"] == []

    def test_with_exam(self, auth_client, sample_patient, db_session):
        _create_exam(db_session, sample_patient["id"])
        resp = auth_client.get("/api/reviews?status=pending_review")
        data = resp.get_json()["data"]
        assert len(data["items"]) >= 1

    def test_pagination(self, auth_client, sample_patient, db_session):
        for _ in range(3):
            _create_exam(db_session, sample_patient["id"])
        resp = auth_client.get("/api/reviews?page=1&per_page=2&status=all")
        data = resp.get_json()["data"]
        assert len(data["items"]) == 2
        assert data["has_more"] is True

    def test_all_excludes_inferring(self, auth_client, sample_patient, db_session):
        _create_exam(db_session, sample_patient["id"], status="inferring")
        ready_exam = _create_exam(db_session, sample_patient["id"], status="pending_review")
        resp = auth_client.get("/api/reviews?status=all")
        data = resp.get_json()["data"]
        item_ids = [item["id"] for item in data["items"]]
        assert ready_exam.id in item_ids
        assert len(data["items"]) == 1


class TestReviewUploadFlow:
    """Upload should stay hidden from review queue until inference finishes."""

    def test_doctor_upload_starts_as_inferring(self, auth_client, sample_patient):
        resp = auth_client.post(
            f"/api/patients/{sample_patient['id']}/exams",
            data={"file": (io.BytesIO(b"fake-image"), "test.png")},
            content_type="multipart/form-data",
        )
        data = resp.get_json()
        assert resp.status_code == 200
        assert data["data"]["exam"]["status"] == "inferring"


class TestReviewDetail:
    """GET /api/reviews/<exam_id>"""

    def test_success(self, auth_client, sample_patient, db_session):
        exam = _create_exam(db_session, sample_patient["id"])
        resp = auth_client.get(f"/api/reviews/{exam.id}")
        data = resp.get_json()
        assert resp.status_code == 200
        assert data["data"]["exam"]["id"] == exam.id

    def test_not_found(self, auth_client):
        resp = auth_client.get("/api/reviews/99999")
        assert resp.status_code == 404


class TestReviewSubmit:
    """POST /api/reviews/<exam_id>/review"""

    def test_submit_review(self, auth_client, sample_patient, db_session):
        exam = _create_exam(db_session, sample_patient["id"])
        resp = auth_client.post(f"/api/reviews/{exam.id}/review", json={
            "decision": "reviewed",
            "note": "娴嬭瘯澶嶆牳澶囨敞",
        })
        data = resp.get_json()
        assert resp.status_code == 200
        assert data["data"]["exam"]["status"] == "reviewed"

    def test_not_found(self, auth_client):
        resp = auth_client.post("/api/reviews/99999/review", json={"decision": "reviewed"})
        assert resp.status_code == 404


class TestReviewDelete:
    """DELETE /api/reviews/<exam_id>"""

    def test_delete_success(self, auth_client, sample_patient, db_session):
        exam = _create_exam(db_session, sample_patient["id"])
        resp = auth_client.delete(f"/api/reviews/{exam.id}")
        assert resp.status_code == 200

        # Verify gone
        resp = auth_client.get(f"/api/reviews/{exam.id}")
        assert resp.status_code == 404

    def test_delete_not_found(self, auth_client):
        resp = auth_client.delete("/api/reviews/99999")
        assert resp.status_code == 404
