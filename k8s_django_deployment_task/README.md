# Django on Amazon EKS

Django deployed on EKS with a private PostgreSQL database in RDS. Helmfile manages the application, AWS Load Balancer Controller, and cert-manager.

Application: [django.pavlo-k8s.ddnsfree.com](https://django.pavlo-k8s.ddnsfree.com/accounts/login/)

## Configuration

| Component | Setup |
|---|---|
| EKS | Kubernetes 1.36, two ARM64 workers in private subnets |
| Application | Gunicorn on port 8080, ClusterIP Service, readiness and liveness probes |
| Image | secure-image-docker:1.0 in private ECR |
| Database | Private RDS PostgreSQL, database hc, application user django_app, TLS required |
| Public access | ALB routing directly to Pod IPs |
| HTTPS | Let’s Encrypt certificate issued by cert-manager and imported into ACM |
| Scaling | HPA: 2–4 replicas at 80% CPU utilization |
| Secrets | SOPS + age, decrypted by helm-secrets during deployment |

## Deploy

The cluster, RDS database, ECR image, and controller IAM role must already exist. You also need AWS CLI, kubectl, Helm, Helmfile, SOPS, age, and helm-secrets.

For infrastructure creation and the first HTTPS setup, follow the [deployment guide](documentation/deployment_guide.md).

Run from this directory with the project's private age key available:

~~~bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/django-eks.txt"

aws eks update-kubeconfig --name django-eks --region us-east-1

helmfile -f helmfile/helmfile.yaml lint
helmfile -f helmfile/helmfile.yaml sync

kubectl rollout status deployment/django -n django --timeout=180s
kubectl exec -n django deployment/django -- python manage.py migrate --noinput
~~~

## Check

~~~bash
kubectl get pods,svc,ingress,hpa -n django
kubectl get issuer,certificate -n django

curl -sS -o /dev/null -w 'HTTP %{http_code}\n' \
  https://django.pavlo-k8s.ddnsfree.com/accounts/login/
~~~

Check that Pods are ready, the certificate reports Ready=True, and the login page returns HTTP 200.

The load test scaled the application to four replicas. After load stopped, CPU utilization dropped from 420% to 1%; downscaling follows the HPA stabilization window.

## Updates

For an application-only update:

~~~bash
helmfile -f helmfile/helmfile.yaml --selector name=django sync
~~~

After changing environment values in the ConfigMap or Secret, restart the Pods:

~~~bash
kubectl rollout restart deployment/django -n django
kubectl rollout status deployment/django -n django --timeout=180s
~~~

Keep the age private key and decrypted secrets out of Git. The encrypted secrets file can be committed.

Certificate renewal needs one manual step: after cert-manager renews the Kubernetes Secret, reimport the certificate into the same ACM ARN. This setup has no automatic Secret-to-ACM synchronization.

Kubernetes handles replica recovery, rolling updates, and scaling. Helm packages the application resources; Helmfile keeps the application and controller releases together.

