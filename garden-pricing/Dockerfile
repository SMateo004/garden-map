FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    gcc g++ gfortran libgomp1 \
    libopenblas-dev liblapack-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# LSTM (opcional): instalar TensorFlow solo si se activa con --build-arg ENABLE_LSTM=1
ARG ENABLE_LSTM=0
RUN if [ "$ENABLE_LSTM" = "1" ]; then pip install --no-cache-dir tensorflow==2.16.1 scikit-learn==1.5.2; fi

COPY main.py .

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
