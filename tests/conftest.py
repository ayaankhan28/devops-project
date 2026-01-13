"""
Pytest configuration and fixtures
"""

import pytest
from fastapi.testclient import TestClient
from app import app, items_db, Item

@pytest.fixture
def client():
    """Create a test client"""
    return TestClient(app)

@pytest.fixture(autouse=True)
def reset_database():
    """Reset the database before each test"""
    items_db.clear()
    items_db.extend([
        Item(id=1, name="Laptop", description="High-performance laptop", price=1200.00, in_stock=True),
        Item(id=2, name="Mouse", description="Wireless mouse", price=25.00, in_stock=True),
        Item(id=3, name="Keyboard", description="Mechanical keyboard", price=80.00, in_stock=False),
    ])
    yield
    items_db.clear()
