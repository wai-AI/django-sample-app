# Docker Image Optimization

Optimization report for [django-sample-app](https://github.com/wai-AI/django-sample-app/tree/feat/ecs-containerization).

Dockerfile: `terraform-aws-ecs-fargate/Dockerfile`.

## Changes

The original Dockerfile already used multi-stage builds, a slim runtime, dependency installation before copying source, APT cleanup, and a non-root user. These features were retained.

Three changes were made:

1. Added a BuildKit pip cache mount and removed `--no-cache-dir` to reuse downloaded packages when installation runs again.
2. Created `/opt/venv` without pip. The builder's global pip installs dependencies into it using `--python`, removing a duplicate pip installation.
3. Removed system `libcurl4t64` after `ldd` confirmed that the installed ARM64 PycURL wheel uses libcurl from `pycurl.libs`. Kept those bundled libraries and `libpq5`, which is required by the installed Psycopg package.

Updated builder instructions:

```
# syntax=docker/dockerfile:1
RUN python -m venv --without-pip /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt /app
RUN --mount=type=cache,target=/root/.cache/pip \
    /usr/local/bin/python -m pip --python /opt/venv \
    install --requirement requirements.txt
```

Updated runtime package installation:

```
RUN apt-get update && \
    apt-get install -y --no-install-recommends libpq5 && \
    rm -rf /var/lib/apt/lists/*
```

## Measurements

Measured on macOS with OrbStack's Docker driver, targeting `linux/arm64`. Elapsed time is the shell's `time` value labelled `total`. Sizes are local image sizes from `docker image inspect`.

| Metric | Baseline | Optimized |
| --- | ---: | ---: |
| Image size, bytes | 276,096,256 | 255,043,935 |
| Build without cache | 25.529 s | 53.234 s |
| Build with full layer cache | 1.323 s | 2.372 s |

**Size reduction: 21.05 MB (7.62%).** Removing pip from the virtual environment saved about 11.10 MB; removing system libcurl saved another 9.95 MB.

An overall build-time improvement was not demonstrated. Package downloads were approximately 7 MB/s in the baseline run and 1.2 MB/s in the final run. These are individual measurements under different network conditions. Base images were already local; `--pull` was not used.

Pip cache reuse was tested separately by changing `-r` to the equivalent `--requirement` option and rebuilding normally. Installation executed, reported `Using cached`, and took 7.2 s. A step marked `CACHED` skips installation entirely and proves layer reuse. Do not use `--no-cache` or `--no-cache-filter` for this pip-cache test: our forced rebuilds downloaded the packages again.

### Repeat the final measurements

```
time docker buildx build \
  --platform linux/arm64 --load --progress=plain --no-cache \
  -f terraform-aws-ecs-fargate/Dockerfile \
  -t django:optimized .
```

Immediately repeat with the same inputs:

```
time docker buildx build \
  --platform linux/arm64 --load --progress=plain \
  -f terraform-aws-ecs-fargate/Dockerfile \
  -t django:optimized .
```

```
docker image inspect django:baseline django:optimized \
  --format '{{index .RepoTags 0}}: {{.Size}} bytes'
```

The baseline tag was preserved before editing. Reproducing it requires the original Dockerfile; changing the tag does not restore the original build.

## Validation

Recorded checks:

- `django:lean-venv`: `pip check` passed, Django/Gunicorn/Psycopg/PycURL imports passed, and Gunicorn's configuration check returned exit code `0`.
- `django:optimized`: Psycopg/PycURL imports and Django WSGI startup passed.
- Static collection, compression, and documentation search database generation completed during the optimized build.
- The optimized candidate served `/accounts/login/` with HTTP `200`.

### Repeat the local HTTP check

Use a temporary SQLite database in `/tmp`, writable by the image's default non-root user:

```
docker run --rm --name django-image-test \
  -p 127.0.0.1:8000:8000 \
  -e DB=sqlite \
  -e DB_NAME=/tmp/hc.sqlite \
  -e DEBUG=False \
  -e ALLOWED_HOSTS=localhost,127.0.0.1 \
  -e SECRET_KEY=local-image-test-only \
  django:optimized sh -c \
  'python manage.py migrate --noinput &&
   exec gunicorn hc.wsgi:application --bind 0.0.0.0:8000'
```

The secret is for this disposable local check only. Once Gunicorn is listening, run in another terminal:

```
curl -sS -L --max-redirs 5 -o /dev/null \
  -w 'HTTP %{http_code}; URL %{url_effective}\n' \
  http://localhost:8000/
```

Expected: `HTTP 200; URL http://localhost:8000/accounts/login/.

