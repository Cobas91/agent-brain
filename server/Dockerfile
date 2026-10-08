FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt requirements.lock ./
RUN pip install --no-cache-dir -r requirements.lock
COPY . .
RUN useradd --uid 10001 --create-home brain
USER brain
CMD ["python", "server.py"]
