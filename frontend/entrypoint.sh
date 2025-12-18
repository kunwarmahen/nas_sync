#!/bin/sh
set -e

# Get API URL from environment or use default
API_URL=${REACT_APP_API_URL:-"http://localhost:5000"}

# Create config.json that frontend can read at runtime
cat > /usr/share/nginx/html/config.json <<JSON
{
  "API_URL": "$API_URL"
}
JSON

echo "✓ Frontend started"
echo "✓ API URL: $API_URL"
echo "✓ Config file created at /config.json"

# Start nginx
exec nginx -g 'daemon off;'
