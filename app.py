"""
FastAPI Application for DevOps CI/CD Project
A simple REST API with health checks and CRUD operations
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="DevOps FastAPI Application",
    description="A simple FastAPI application for CI/CD demonstration",
    version="1.0.0"
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Pydantic models
class Item(BaseModel):
    id: int
    name: str
    description: Optional[str] = None
    price: float
    in_stock: bool = True

class ItemCreate(BaseModel):
    name: str
    description: Optional[str] = None
    price: float
    in_stock: bool = True

# In-memory database (for demonstration)
items_db: List[Item] = [
    Item(id=1, name="Laptop", description="High-performance laptop", price=1200.00, in_stock=True),
    Item(id=2, name="Mouse", description="Wireless mouse", price=25.00, in_stock=True),
    Item(id=3, name="Keyboard", description="Mechanical keyboard", price=80.00, in_stock=False),
]

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "message": "Welcome to DevOps FastAPI Application",
        "version": "1.0.0",
        "endpoints": {
            "health": "/health",
            "items": "/items",
            "docs": "/docs"
        }
    }

@app.get("/health")
async def health_check():
    """Health check endpoint for monitoring"""
    logger.info("Health check requested")
    return {
        "status": "healthy",
        "service": "devops-fastapi",
        "version": "1.0.0"
    }

@app.get("/items", response_model=List[Item])
async def get_items():
    """Get all items"""
    logger.info(f"Fetching all items. Total: {len(items_db)}")
    return items_db

@app.get("/items/{item_id}", response_model=Item)
async def get_item(item_id: int):
    """Get a specific item by ID"""
    logger.info(f"Fetching item with ID: {item_id}")
    for item in items_db:
        if item.id == item_id:
            return item
    logger.warning(f"Item with ID {item_id} not found")
    raise HTTPException(status_code=404, detail=f"Item with ID {item_id} not found")

@app.post("/items", response_model=Item, status_code=201)
async def create_item(item: ItemCreate):
    """Create a new item"""
    # Generate new ID
    new_id = max([i.id for i in items_db], default=0) + 1
    new_item = Item(id=new_id, **item.dict())
    items_db.append(new_item)
    logger.info(f"Created new item with ID: {new_id}")
    return new_item

@app.put("/items/{item_id}", response_model=Item)
async def update_item(item_id: int, item: ItemCreate):
    """Update an existing item"""
    logger.info(f"Updating item with ID: {item_id}")
    for idx, existing_item in enumerate(items_db):
        if existing_item.id == item_id:
            updated_item = Item(id=item_id, **item.dict())
            items_db[idx] = updated_item
            logger.info(f"Successfully updated item with ID: {item_id}")
            return updated_item
    logger.warning(f"Item with ID {item_id} not found for update")
    raise HTTPException(status_code=404, detail=f"Item with ID {item_id} not found")

@app.delete("/items/{item_id}")
async def delete_item(item_id: int):
    """Delete an item"""
    logger.info(f"Deleting item with ID: {item_id}")
    for idx, item in enumerate(items_db):
        if item.id == item_id:
            deleted_item = items_db.pop(idx)
            logger.info(f"Successfully deleted item with ID: {item_id}")
            return {"message": f"Item {item_id} deleted successfully", "item": deleted_item}
    logger.warning(f"Item with ID {item_id} not found for deletion")
    raise HTTPException(status_code=404, detail=f"Item with ID {item_id} not found")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
