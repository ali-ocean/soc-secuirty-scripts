#!/bin/bash

echo "=== Security Dashboard Deployment ==="

if ! command -v python3 &> /dev/null; then
    echo "Python 3 is required"
    exit 1
fi

echo "Installing Python dependencies..."
python3 -m pip install --user -r requirements.txt

echo "Checking Supabase connection..."
if [ -z "$VITE_SUPABASE_URL" ]; then
    if [ -f .env ]; then
        export $(cat .env | grep -v '^#' | xargs)
    else
        echo "Error: .env file not found"
        exit 1
    fi
fi

echo "Database schema already created via Supabase migration"

echo "Starting Flask application on port 5000..."
echo "Access dashboard at: http://localhost:5000"
echo ""
echo "First time setup:"
echo "1. Register at /register"
echo "2. Promote user to admin via Supabase dashboard:"
echo "   UPDATE profiles SET role = 'admin' WHERE email = 'your-email@example.com';"
echo ""
echo "Start worker in separate terminal:"
echo "   python3 worker.py"
echo ""

python3 app.py
