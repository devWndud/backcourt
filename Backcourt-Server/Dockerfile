FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    ADMIN_STATIC_DIR=/app/admin

WORKDIR /app

COPY Backcourt-Server/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

RUN useradd --create-home --uid 10001 backcourt
COPY --chown=backcourt:backcourt Backcourt-Server/app ./app
COPY --chown=backcourt:backcourt Backcourt-Admin ./admin
USER backcourt

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--proxy-headers"]
