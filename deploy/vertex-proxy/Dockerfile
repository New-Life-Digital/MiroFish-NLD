FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY proxy.py .
ENV PYTHONUNBUFFERED=1 USAGE_LOG=/data/usage.jsonl
VOLUME /data
EXPOSE 8080
CMD ["python", "proxy.py"]
