FROM python:3.12-slim

WORKDIR /app

# Install audio dependencies for pyttsx3/playsound (best-effort in container)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        espeak-ng \
        libespeak-ng1 \
        alsa-utils \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Config and data are mounted as volumes, not baked into the image
VOLUME ["/app/config", "/app/data"]

CMD ["python", "main.py"]
