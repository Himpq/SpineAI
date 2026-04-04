# -*- coding: utf-8 -*-
"""Shared pytest fixtures for Spine FUPT backend tests."""
import os
import sys
from unittest.mock import patch

import pytest

# Ensure the project root is on sys.path so `import app` works
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

# Override DB URI *before* importing app (which runs db.create_all at import time)
os.environ["SQLALCHEMY_DATABASE_URI_OVERRIDE"] = "sqlite://"


def _make_app():
    """Import the app module and reconfigure for testing."""
    from app import app, db, bootstrap_admin

    app.config.update(
        TESTING=True,
        SQLALCHEMY_DATABASE_URI="sqlite://",
        SERVER_NAME="localhost",
        WTF_CSRF_ENABLED=False,
    )

    # Recreate tables in the in-memory database
    with app.app_context():
        db.drop_all()
        db.create_all()
        bootstrap_admin()

    return app, db


_app, _db = _make_app()


@pytest.fixture()
def app():
    """Yield a configured Flask app with a fresh database per test."""
    with _app.app_context():
        _db.drop_all()
        _db.create_all()
        # Create default admin user
        from app import bootstrap_admin
        bootstrap_admin()
        yield _app
        _db.session.rollback()


@pytest.fixture()
def client(app):
    """Flask test client."""
    return app.test_client()


@pytest.fixture()
def db_session(app):
    """Direct access to SQLAlchemy session."""
    return _db.session


def _login(client, username="admin", password="admin123"):
    """Helper: login and return response."""
    return client.post("/api/auth/login", json={
        "username": username,
        "password": password,
    })


@pytest.fixture()
def auth_client(client):
    """A test client already logged in as admin."""
    resp = _login(client)
    assert resp.status_code == 200, f"Login failed: {resp.get_json()}"
    return client


@pytest.fixture()
def doctor_user(app):
    """Create and return a doctor user."""
    from app import User, db as appdb
    user = User(
        username="drtest",
        display_name="测试医生",
        role="doctor",
        is_active=True,
        module_permissions='["overview","followup","review","chat","questionnaire","status"]',
    )
    user.set_password("doctor123")
    appdb.session.add(user)
    appdb.session.commit()
    return user


@pytest.fixture()
def doctor_client(client, doctor_user):
    """A test client logged in as doctor."""
    resp = _login(client, "drtest", "doctor123")
    assert resp.status_code == 200
    return client


@pytest.fixture()
def sample_patient(auth_client):
    """Create a sample patient via API, return its data dict."""
    resp = auth_client.post("/api/patients", json={
        "name": "测试患者",
        "age": 25,
        "sex": "女",
        "phone": "13800138000",
    })
    assert resp.status_code == 200
    data = resp.get_json()
    return data["data"]["patient"]


# Mock expensive external calls globally
@pytest.fixture(autouse=True)
def mock_inference():
    """Prevent real inference calls during tests."""
    with patch("app.run_remote_inference", return_value=None):
        yield


@pytest.fixture(autouse=True)
def mock_ws_broadcast():
    """Prevent WebSocket broadcast during tests."""
    with patch("app.ws_broadcast"):
        yield
