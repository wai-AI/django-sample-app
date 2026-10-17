# Django deployment on EKS

| Setting | Value |
|---|---|
| Region / cluster | us-east-1 / django-eks, Kubernetes 1.36 |
| Image | 022784798189.dkr.ecr.us-east-1.amazonaws.com/secure-image-docker:1.0 |
| Application | Namespace django, Gunicorn on port 8080 |
| Database | PostgreSQL 17.9, database hc, user django_app |
| Scaling | 2–4 replicas, CPU target 80% |

## Cluster and image

The EKS configuration is in infra/eks-cluster.yaml. It creates two t4g.small workers in private subnets across two Availability Zones, a single NAT Gateway, and an IAM OIDC provider.

~~~bash
export AWS_DEFAULT_REGION=us-east-1

eksctl create cluster -f infra/eks-cluster.yaml --dry-run
eksctl create cluster -f infra/eks-cluster.yaml

aws eks update-kubeconfig --name django-eks --region us-east-1
kubectl get nodes -L kubernetes.io/arch
kubectl top nodes
~~~

Both nodes must be Ready and report arm64. Metrics Server was installed with the cluster.

The existing secure-docker:1.0 image already supported ARM64 and ran as a non-root user. Its default port was 8000; the Deployment overrides Gunicorn's arguments to listen on 8080:

~~~bash
gunicorn hc.wsgi:application --bind 0.0.0.0:8080
~~~

Publish the image to ECR:

~~~bash
django_registry=022784798189.dkr.ecr.us-east-1.amazonaws.com

aws ecr create-repository --repository-name secure-image-docker
aws ecr get-login-password \
  | docker login --username AWS --password-stdin "$django_registry"

docker tag secure-docker:1.0 "$django_registry/secure-image-docker:1.0"
docker push "$django_registry/secure-image-docker:1.0"
~~~

## Database

RDS was created in the EKS VPC with these settings:

- Subnet group django-rds-private, using private subnets in both Availability Zones.
- A dedicated security group allowing TCP 5432 from the EKS workers' security group.
- PostgreSQL 17.9 on db.t4g.micro, 20 GiB encrypted gp3 storage, Single-AZ.
- Database hc, administrator hcadmin, public access disabled.

The endpoint for this deployment is django-postgres.cwjy8gi8ua39.us-east-1.rds.amazonaws.com. Update the Helm values if the database is recreated.

A temporary postgres:17-alpine Pod was used to connect from inside the cluster with sslmode=require. As hcadmin, create the application role:

~~~sql
CREATE ROLE django_app LOGIN;
\password django_app
GRANT CONNECT ON DATABASE hc TO django_app;
GRANT USAGE, CREATE ON SCHEMA public TO django_app;

\connect hc django_app
SELECT current_database(), current_user;
\conninfo
~~~

The check should show database hc, user django_app, and an SSL connection. Use the django_app password in the application Secret.

## Secrets

From this point, run commands inside the task directory:

~~~bash
cd k8s_django_deployment_task
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/django-eks.txt"
~~~

SOPS and age encrypt helmfile/secrets.yaml. Helmfile uses helm-secrets 4.7.8 to decrypt it during deployment. The private age key stays outside the repository; .sops.yaml contains its public recipient.

Edit the file through SOPS:

~~~bash
sops edit helmfile/secrets.yaml
~~~

Its decrypted contents have this structure:

~~~yaml
secrets:
  DB_PASSWORD: "password-for-django_app"
  SECRET_KEY: "one-random-key-shared-by-all-replicas"
~~~

Replace both placeholders. Generate SECRET_KEY once with openssl rand -hex 32.

~~~bash
sops filestatus helmfile/secrets.yaml
sops decrypt helmfile/secrets.yaml > /dev/null
~~~

Commit the encrypted file. Keep private keys and decrypted copies out of Git.

## Helm deployment

Before the first sync, create an IAM role for the AWS Load Balancer Controller using the policy in infra/aws-load-balancer-iam-policy.json. Associate it with the kube-system/aws-load-balancer-controller ServiceAccount through eksctl. The controller chart uses that existing account with serviceAccount.create set to false.

Helmfile installs:

| Release | Version |
|---|---|
| AWS Load Balancer Controller | 3.6.0 |
| cert-manager | v1.21.2, CRDs enabled |
| Django | Local Helm chart |

The Django release depends on both controllers through Helmfile's needs field.

The application chart provides the ConfigMap, Secret, Deployment, ClusterIP Service, Ingress, HPA, Issuer, and Certificate. The container has:

- CPU/memory requests of 100m and 128Mi; limits of 500m and 512Mi.
- TCP readiness and liveness probes on port 8080.
- Environment variables from the ConfigMap and Secret.
- Its Pod IP appended to ALLOWED_HOSTS for ALB health checks.

For the first deployment, leave ingress.certificateArn empty and use HTTP in SITE_ROOT. This lets the ALB serve the certificate challenge before HTTPS is configured.

Check the database settings in values.yaml:

~~~yaml
config:
  DB: "postgres"
  DB_HOST: "django-postgres.cwjy8gi8ua39.us-east-1.rds.amazonaws.com"
  DB_PORT: "5432"
  DB_NAME: "hc"
  DB_USER: "django_app"
  DB_SSLMODE: "require"
~~~

Deploy and run migrations:

~~~bash
helmfile -f helmfile/helmfile.yaml lint
helmfile -f helmfile/helmfile.yaml sync

kubectl rollout status deployment/django -n django --timeout=180s
kubectl exec -n django deployment/django -- python manage.py migrate --noinput
kubectl get pods,svc,hpa -n django
~~~

## Domain and HTTPS

The Ingress uses class alb and target type ip. The controller creates an internet-facing ALB that routes directly to Pod IPs. The application's Service stays ClusterIP.

Get the ALB address:

~~~bash
kubectl get ingress django -n django
~~~

In Dynu, create a CNAME for django.pavlo-k8s.ddnsfree.com pointing to that address. Use the hostname without a URL scheme or path.

~~~bash
dig +short CNAME django.pavlo-k8s.ddnsfree.com
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' \
  http://django.pavlo-k8s.ddnsfree.com/accounts/login/
~~~

The domain must be in ALLOWED_HOSTS and match ingress.host. The login page returned HTTP 200 once DNS and host settings were correct.

### Issue the certificate

cert-manager uses HTTP-01 validation through the existing django Ingress. The ALB health check uses / with success codes 200,302 so it also accepts the temporary challenge solver.

~~~bash
kubectl wait -n django \
  --for=condition=Ready certificate/django-tls --timeout=300s
kubectl get issuer,certificate -n django
~~~

Both resources should report Ready=True. The certificate and key are stored in the django-tls Secret.

### Attach it to the ALB

ALB requires a certificate in ACM. Export the Kubernetes certificate, split the leaf certificate from its chain, and import it:

~~~bash
django_tls_dir=$(mktemp -d)

kubectl get secret django-tls -n django -o jsonpath='{.data.tls\.crt}' \
  | base64 -D > "$django_tls_dir/fullchain.pem"
kubectl get secret django-tls -n django -o jsonpath='{.data.tls\.key}' \
  | base64 -D > "$django_tls_dir/key.pem"

openssl x509 -in "$django_tls_dir/fullchain.pem" \
  -out "$django_tls_dir/certificate.pem"
awk '/-----BEGIN CERTIFICATE-----/ { n++ } n > 1 { print }' \
  "$django_tls_dir/fullchain.pem" > "$django_tls_dir/chain.pem"
chmod 600 "$django_tls_dir"/*.pem

django_acm_arn=$(aws acm import-certificate \
  --certificate "fileb://$django_tls_dir/certificate.pem" \
  --certificate-chain "fileb://$django_tls_dir/chain.pem" \
  --private-key "fileb://$django_tls_dir/key.pem" \
  --query CertificateArn --output text)

echo "$django_acm_arn"

rm -f "$django_tls_dir"/*.pem
rmdir "$django_tls_dir"
~~~

Set ingress.certificateArn to the returned ARN and update:

~~~yaml
config:
  SITE_ROOT: "https://django.pavlo-k8s.ddnsfree.com"
  SECURE_PROXY_SSL_HEADER: "HTTP_X_FORWARDED_PROTO,https"
~~~

The Ingress template then enables port 443 and redirects HTTP to HTTPS.

~~~bash
helmfile -f helmfile/helmfile.yaml --selector name=django sync
kubectl rollout restart deployment/django -n django
kubectl rollout status deployment/django -n django --timeout=180s

curl -sS -L -o /dev/null \
  -w 'HTTP %{http_code}\nURL: %{url_effective}\n' \
  http://django.pavlo-k8s.ddnsfree.com/accounts/login/
~~~

The final check should return HTTP 200 and an HTTPS URL with a valid certificate.

## Autoscaling

The HPA scales between two and four replicas at 80% CPU utilization. This percentage is relative to the 100m CPU request: 80% means roughly 80m per Pod.

Generate load for up to five minutes:

~~~bash
kubectl run django-load -n django \
  --image=busybox:1.37 --restart=Never \
  --overrides='{"apiVersion":"v1","spec":{"activeDeadlineSeconds":300}}' \
  --command -- sh -c '
worker() {
  while true; do
    wget -q -T 5 -O /dev/null \
      --header="Host: django.pavlo-k8s.ddnsfree.com" \
      http://django:8080/accounts/login/
  done
}
for i in 1 2 3 4 5 6 7 8; do worker & done
wait
'
~~~

Watch from another terminal, then delete the load Pod when finished:

~~~bash
kubectl get hpa django -n django --watch
~~~

~~~bash
kubectl delete pod django-load -n django
~~~

The test reached four replicas at 420% CPU utilization. After load stopped, CPU fell to 1%. Allow about five minutes for downscale stabilization, then check that the replica count returns to two.

## Problems and fixes

| Problem | Fix |
|---|---|
| PostgreSQL authentication failed | Reset django_app's password through hcadmin, update the SOPS file, sync, and restart the Deployment. |
| Django returned HTTP 400 | Add the domain to ALLOWED_HOSTS and append the Pod IP for ALB health checks. |
| Traefik's NLB remained pending with OperationNotPermitted | Use the ALB path, which worked in this account, and remove Traefik. |
| psql exited before accepting a password | Start a sleeping client Pod, wait until it is ready, then run psql through kubectl exec -it. |
| HPA kept four replicas after load stopped | Wait for the downscale stabilization window. |

The cause of the NLB account restriction was not confirmed. The final deployment uses ALB only.

## Updates and cleanup

After changing ConfigMap or Secret environment values, sync the release and restart the Deployment. For an image update, push a new tag, change the Helm values, and sync.

cert-manager renews the Kubernetes certificate, but this setup does not copy renewals into ACM automatically. Repeat the export and import with the existing ACM ARN passed as --certificate-arn. This keeps the ALB attached to the same certificate.

To remove the environment:

1. Keep an RDS snapshot if the data is needed.
2. Uninstall Django and wait for the ALB to disappear while its controller is still running.
3. Uninstall the controllers and remove the controller's IAM service account and role.
4. Delete RDS, its subnet group, and its security group before deleting the EKS VPC.
5. Delete EKS and any remaining unused ACM certificates, ECR images, and IAM policies.

Kubernetes handles replicas, recovery, and scaling. Helm keeps the application resources in one chart, and Helmfile installs the application and its controllers in the required order.
