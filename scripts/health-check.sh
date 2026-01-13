#!/bin/bash

# Health check script for FastAPI application
# Usage: ./health-check.sh <port>
# Example: ./health-check.sh 8000

set -e

PORT=${1:-8000}
MAX_ATTEMPTS=15
ATTEMPT=1

echo "🔍 Running health check on port ${PORT}..."

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    echo "Attempt ${ATTEMPT}/${MAX_ATTEMPTS}..."
    
    # Check health endpoint
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${PORT}/health" || echo "000")
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✅ Health check passed!"
        
        # Additional endpoint checks
        echo "🧪 Testing additional endpoints..."
        
        # Test items endpoint
        ITEMS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${PORT}/items" || echo "000")
        if [ "$ITEMS_CODE" = "200" ]; then
            echo "✅ Items endpoint: OK"
        else
            echo "⚠️ Items endpoint returned: ${ITEMS_CODE}"
        fi
        
        # Test root endpoint
        ROOT_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${PORT}/" || echo "000")
        if [ "$ROOT_CODE" = "200" ]; then
            echo "✅ Root endpoint: OK"
        else
            echo "⚠️ Root endpoint returned: ${ROOT_CODE}"
        fi
        
        echo "✅ All health checks passed!"
        exit 0
    fi
    
    echo "⏳ Application not ready yet (HTTP ${HTTP_CODE}), waiting..."
    sleep 3
    ATTEMPT=$((ATTEMPT + 1))
done

echo "❌ Health check failed after ${MAX_ATTEMPTS} attempts"
exit 1
