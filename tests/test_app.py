"""
Comprehensive test suite for FastAPI application
"""


def test_root_endpoint(client):
    """Test root endpoint"""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert "message" in data
    assert "version" in data
    assert data["version"] == "1.0.0"


def test_health_check(client):
    """Test health check endpoint"""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["service"] == "devops-fastapi"
    assert data["version"] == "1.0.0"


def test_get_all_items(client):
    """Test getting all items"""
    response = client.get("/items")
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) == 3
    assert data[0]["name"] == "Laptop"


def test_get_item_by_id(client):
    """Test getting a specific item"""
    response = client.get("/items/1")
    assert response.status_code == 200
    data = response.json()
    assert data["id"] == 1
    assert data["name"] == "Laptop"
    assert data["price"] == 1200.00


def test_get_item_not_found(client):
    """Test getting a non-existent item"""
    response = client.get("/items/999")
    assert response.status_code == 404
    data = response.json()
    assert "not found" in data["detail"].lower()


def test_create_item(client):
    """Test creating a new item"""
    new_item = {
        "name": "Monitor",
        "description": "4K Monitor",
        "price": 350.00,
        "in_stock": True
    }
    response = client.post("/items", json=new_item)
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Monitor"
    assert data["price"] == 350.00
    assert "id" in data

    # Verify item was added
    response = client.get("/items")
    assert len(response.json()) == 4


def test_create_item_minimal(client):
    """Test creating item with minimal fields"""
    new_item = {
        "name": "Headphones",
        "price": 50.00
    }
    response = client.post("/items", json=new_item)
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Headphones"
    assert data["in_stock"] is True  # Default value


def test_update_item(client):
    """Test updating an existing item"""
    updated_item = {
        "name": "Updated Laptop",
        "description": "Ultra high-performance laptop",
        "price": 1500.00,
        "in_stock": False
    }
    response = client.put("/items/1", json=updated_item)
    assert response.status_code == 200
    data = response.json()
    assert data["id"] == 1
    assert data["name"] == "Updated Laptop"
    assert data["price"] == 1500.00
    assert data["in_stock"] is False


def test_update_item_not_found(client):
    """Test updating a non-existent item"""
    updated_item = {
        "name": "Ghost Item",
        "price": 100.00
    }
    response = client.put("/items/999", json=updated_item)
    assert response.status_code == 404


def test_delete_item(client):
    """Test deleting an item"""
    response = client.delete("/items/1")
    assert response.status_code == 200
    data = response.json()
    assert "deleted successfully" in data["message"].lower()

    # Verify item was deleted
    response = client.get("/items")
    assert len(response.json()) == 2

    # Verify deleted item is not accessible
    response = client.get("/items/1")
    assert response.status_code == 404


def test_delete_item_not_found(client):
    """Test deleting a non-existent item"""
    response = client.delete("/items/999")
    assert response.status_code == 404


def test_create_item_invalid_data(client):
    """Test creating item with invalid data"""
    invalid_item = {
        "name": "Invalid",
        # Missing required 'price' field
    }
    response = client.post("/items", json=invalid_item)
    assert response.status_code == 422  # Validation error


def test_item_price_validation(client):
    """Test item price must be a number"""
    invalid_item = {
        "name": "Test",
        "price": "not a number"
    }
    response = client.post("/items", json=invalid_item)
    assert response.status_code == 422


def test_multiple_operations(client):
    """Test multiple CRUD operations in sequence"""
    # Create
    new_item = {"name": "Tablet", "price": 400.00}
    response = client.post("/items", json=new_item)
    assert response.status_code == 201
    item_id = response.json()["id"]

    # Read
    response = client.get(f"/items/{item_id}")
    assert response.status_code == 200

    # Update
    updated = {"name": "Premium Tablet", "price": 500.00}
    response = client.put(f"/items/{item_id}", json=updated)
    assert response.status_code == 200
    assert response.json()["price"] == 500.00

    # Delete
    response = client.delete(f"/items/{item_id}")
    assert response.status_code == 200

    # Verify deletion
    response = client.get(f"/items/{item_id}")
    assert response.status_code == 404
