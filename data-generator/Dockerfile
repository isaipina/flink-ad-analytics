FROM python:3.9-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy data generator script
COPY generate_events.py .

# Make script executable
RUN chmod +x generate_events.py

CMD ["python", "generate_events.py"]