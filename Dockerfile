FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Dependencies first: this layer is cached and rebuilt only when requirements.txt changes
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Application code
COPY app/ .

# Run as an unprivileged user
RUN useradd --create-home --uid 10001 portal
USER portal

EXPOSE 5000

CMD ["python", "app.py"]
