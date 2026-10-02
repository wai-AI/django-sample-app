FROM python:3.12-slim-bookworm AS builder
WORKDIR /app
RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential libcurl4-openssl-dev libssl-dev libpq-dev && \
    rm -rf /var/lib/apt/lists/*
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt /app
RUN pip install -r requirements.txt --no-cache-dir

FROM python:3.12-slim-bookworm AS runtime
WORKDIR /app
RUN apt-get update && \
    apt-get install -y --no-install-recommends libcurl4 libpq5 && \
    rm -rf /var/lib/apt/lists/*
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY . /app
RUN python manage.py collectstatic --noinput && python manage.py compress --force
RUN useradd --create-home --uid 10001 appuser
USER appuser
EXPOSE 8000
CMD ["gunicorn", "hc.wsgi:application", "--bind", "0.0.0.0:8000"]
