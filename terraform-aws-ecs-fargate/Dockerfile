# syntax=docker/dockerfile:1

FROM python:3.12 AS builder
WORKDIR /app
RUN python -m venv --without-pip /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt /app
RUN --mount=type=cache,target=/root/.cache/pip \
    /usr/local/bin/python -m pip --python /opt/venv \
    install --requirement requirements.txt

FROM python:3.12-slim AS runtime
WORKDIR /app
RUN apt-get update && \
    apt-get install -y --no-install-recommends libpq5 && \
    rm -rf /var/lib/apt/lists/*
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY . /app
RUN python manage.py collectstatic --noinput && \
    python manage.py compress --force && \
    python manage.py populate_searchdb
RUN useradd --create-home --uid 10001 appuser
USER appuser
EXPOSE 8000
CMD ["gunicorn", "hc.wsgi:application", "--bind", "0.0.0.0:8000"]
