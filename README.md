# Kubernetes Security Enhancement

## Scope

This task extended the existing Django Helm deployment with Pod security settings, Pod Security Admission, NetworkPolicy, RBAC, and Helm template tests. Initial checks ran in kind. Deployment and access-control tests then ran on the `django-eks` EKS cluster in the `django` namespace, with a private PostgreSQL RDS database.

The review focused on application manifests, cluster configuration, and the runtime checks described below. It was not a full cluster vulnerability audit.

## Security assessment and changes

The existing image already used a non-root user. The chart needed explicit security settings and controls to prevent future deployments from weakening that configuration. The changes followed Kubernetes guidance on [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) and [least-privilege access](https://kubernetes.io/docs/concepts/security/rbac-good-practices/).

| Risk | Change and purpose |
| --- | --- |
| A compromised container gaining unnecessary privileges | Both the Django Deployment and migration Job use `runAsNonRoot: true`, UID/GID `10001`, `privileged: false`, `allowPrivilegeEscalation: false`, and drop all Linux capabilities. These settings limit the privileges available to an attacker. |
| Unnecessary access to system calls | The Pod security context selects the `RuntimeDefault` seccomp profile, applying the container runtime's syscall restrictions. |
| Modification of application files | Containers use `readOnlyRootFilesystem: true`. A separate `emptyDir` mounted at `/tmp`, with a `128Mi` size limit, provides temporary writable storage. |
| Theft of Kubernetes API credentials | A dedicated application ServiceAccount has `automountServiceAccountToken: false`. The application does not need Kubernetes API access and receives no application-specific RBAC permissions. |
| Future Pods bypassing the security settings | The namespace enforces the Restricted Pod Security Standard. This makes admission checks independent of the Helm templates. |
| Unrestricted traffic between workloads | A NetworkPolicy selects all Pods in the application namespace and restricts both incoming and outgoing connections. |
| Excessive user permissions | A namespace-scoped viewer Role and RoleBinding provide read access without granting access to Secrets or permission to modify workloads. |
| Exposure of credentials in Git | Secret values are stored in a SOPS-encrypted file. The private age key stays outside the repository. Kubernetes Secret base64 encoding alone does not provide this protection. |

Existing CPU and memory requests and limits were retained. The reviewed EKS configuration also restricts public API access to the administrator's IP address, enables private API access and API/audit/authenticator logging, and uses private worker nodes with encrypted volumes and SSH disabled.

RDS is private and encrypted at rest. Its security group allows PostgreSQL connections from the cluster security group. Django connects with `DB_SSLMODE=require` and uses the separate `django_app` database role. That role has no superuser, database-creation, or role-creation privileges.

## Implementation details

### Pod Security Admission

The namespace manifest enables `enforce`, `warn`, and `audit` at the `restricted` level, pinned to `v1.35`. This is the policy version used in the tests, including on EKS Kubernetes 1.36. The namespace was bootstrapped with these labels before application installation. It was then adopted by the Helm release, and `templates/ns.yaml` now maintains the labels. The `helm.sh/resource-policy: keep` annotation instructs Helm to preserve the namespace on uninstall. [Pod Security Admission documentation](https://kubernetes.io/docs/concepts/security/pod-security-admission/).

### NetworkPolicy

NetworkPolicy enforcement was enabled in the EKS VPC CNI. The tested application policy allows:

- Incoming TCP traffic on port `8080` from Pods labelled `access=allowed` in the `security-tests` namespace.
- Outgoing DNS queries to CoreDNS on UDP/TCP port `53`.
- Outgoing PostgreSQL connections on TCP port `5432` to the two private subnet CIDRs containing RDS: `10.20.64.0/19` and `10.20.96.0/19`.

For the Helm connection test, an additional ingress rule permits the test Job's Pods to reach Django on port `8080`. A separate egress policy selects only those test Pods and allows that connection to application Pods in the same namespace.

The database rule permits that port across those subnets, rather than identifying one database by hostname. This avoids depending on a fixed RDS IP address but leaves a broader destination range. The RDS security group provides an additional access restriction. [NetworkPolicy documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/).

### RBAC

The `django-viewer` Role grants `get`, `list`, and `watch` for Pods, Services, Events, Deployments, ReplicaSets, and Jobs, plus `get` for Pod logs. A RoleBinding assigns it to the `django-viewers` group in the `django` namespace.

Authorization was tested using impersonation. A real human user's IAM authentication and mapping to this group were not configured as part of these tests.

## Verification

| Check | Result |
| --- | --- |
| Helm chart lint | Passed with no chart errors. |
| Helm template unit tests | All 6 tests passed. They cover non-root execution, seccomp, privilege restrictions, the read-only root filesystem, ServiceAccount selection, and temporary storage in the Deployment and migration Job. |
| Runtime hardening in kind | UID/GID `10001`, zero effective capabilities, `NoNewPrivs: 1`, and `Seccomp: 2`. The root filesystem was read-only, `/tmp` was writable, and no ServiceAccount token was mounted. |
| EKS application deployment | Helm installation completed successfully, including the migration hook. The Django Pod was `1/1 Running`. |
| Final chart upgrade and connection test | The upgrade completed with status `deployed`, revision `2`. Running `helm test django` completed the `django-connection-test` Job with phase `Succeeded`. The Job requests `/accounts/login/` through the Service and requires HTTP `200`. |
| Application response | Through port-forwarding, `/` returned HTTP `302`, followed by HTTP `200` at `/accounts/login/`. |
| PSA on EKS | A server-side dry run of a Pod missing the required security settings was rejected with `restricted:v1.35` violations. |
| RBAC on EKS | Listing Pods returned `yes`; deleting Pods and reading Secrets returned `no`. |
| NetworkPolicy on EKS | The allowed probe received HTTP `200` from Django. After its label changed to `access=denied`, the connection was blocked. |
| Egress on EKS | Django could connect to RDS on port `5432`; its connection to an unrelated probe on port `8080` was blocked. The probe had first been confirmed reachable from another test Pod. |

The network checks used connections between Pods. Port-forwarding was used only to check the application response. Unit tests validate rendered manifests; the [Helm test hook](https://helm.sh/docs/topics/chart_tests/) checks the running application through its Service.

## Repository structure

The main files for this task are:

```text
k8s_security_enhancement/
├── charts/
│   ├── cert-manager-v1.13.1.tgz
│   ├── ingress-nginx-4.8.1.tgz
│   └── metrics-server-3.11.0.tgz
├── Chart.yaml
├── .helmignore
├── values.yaml
├── templates/
│   ├── configmap.yaml
│   ├── deployment.yaml
│   ├── _helpers.tpl
│   ├── hpa.yaml
│   ├── ingress.yaml
│   ├── issuer.yaml
│   ├── migrations.yaml
│   ├── networkpolicy.yaml
│   ├── NOTES.txt
│   ├── ns.yaml
│   ├── pv.yaml
│   ├── pvc.yaml
│   ├── rbac.yaml
│   ├── secret.yaml
│   ├── serviceaccount.yaml
│   ├── service.yaml
│   ├── storage-class.yaml
│   └── tests/
│       └── test-connection.yaml
└── tests/
    └── pod_security_test.yaml
helmfile.yaml                  # Application release and selected values
helm_secrets/
├── .sops.yaml
├── django_config.yaml
└── django_secret.yaml         # Encrypted secret values
infra/
├── eks-cluster.yaml
├── django-namespace.yaml
├── eks-values.yaml
├── local-values.yaml
└── network-test.yaml
```

I consider this the best fit for this task because the application resources and security controls are reviewed together in one chart, while infrastructure setup and environment-specific values remain separate. `_helpers.tpl` provides a reusable naming helper, and `NOTES.txt` displays access and test commands after deployment.

The two test directories have different purposes: `tests/` contains local template unit tests, and `templates/tests/` contains the Job run by `helm test`. The additional migration, RBAC, and NetworkPolicy files implement this application's requirements alongside the files listed in the assignment.

The root Helmfile selects the tested EKS values and encrypted secrets. Non-secret configuration stays separate from credentials; the current EKS profile supplies the configuration used in the AWS tests. `infra/django-namespace.yaml` supports initial namespace creation, while the chart manages it after adoption.

The three chart archives match the versions specified in the assignment. They are declared as dependencies in `Chart.yaml` and disabled through `bundledCharts` values. This includes the requested packages without installing extra controllers or duplicating the EKS Metrics Server add-on in the tested environment.

## Limits of the tested setup

The AWS profile runs one application replica and a Single-AZ database. Ingress, persistent static-file storage, and autoscaling are disabled; static files come from the image, and access is through port-forwarding. This is a security lab configuration, not a highly available public deployment.

Container-image vulnerability scanning was not performed. The database connection requires TLS, but `sslmode=require` does not provide the server identity verification offered by `verify-full`.
