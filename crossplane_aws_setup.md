# Crossplane AWS EC2 Setup — RKE2 Cluster

Steps performed to provision 2 EC2 instances (with VPC networking, security group,
and SSH key pair) via Crossplane from the rke2 cluster, plus how to tear it all down.

Manifest: `ec2-instances-crossplane.yaml` (same directory as this file).

## 0. Prerequisites found on this cluster

- `kubectl config current-context` → `default` (rke2 cluster, control plane at `10.0.0.100`)
- Crossplane core (`crossplane-2.3.4`) was already installed via Helm in the
  `crossplane-system` namespace.

## 1. Fix missing Crossplane core CRDs

This cluster's Crossplane install was missing 4 CRDs that provider installation
depends on (`providerrevisions`, `functionrevisions`, `locks`,
`compositeresourcedefinitions`). Without these, installing any provider gets stuck
with errors like `cannot create object: the server could not find the requested
resource (post providerrevisions.pkg.crossplane.io)`.

Fetch and apply the missing CRDs from the matching Crossplane version (adjust the
version tag if your cluster runs a different one — check with
`helm list -n crossplane-system`):

```bash
CP_VERSION=v2.3.4

for crd in \
  pkg.crossplane.io_providerrevisions.yaml \
  pkg.crossplane.io_functionrevisions.yaml \
  pkg.crossplane.io_locks.yaml \
  apiextensions.crossplane.io_compositeresourcedefinitions.yaml
do
  curl -sL -o "$crd" "https://raw.githubusercontent.com/crossplane/crossplane/${CP_VERSION}/cluster/crds/${crd}"
  kubectl apply -f "$crd"
done
```

To check whether your cluster is missing any core CRDs in the future, diff installed
vs. expected:

```bash
kubectl get crds -o name | sed 's#customresourcedefinition.apiextensions.k8s.io/##' | grep 'crossplane\.io$' | sort
curl -sL "https://api.github.com/repos/crossplane/crossplane/contents/cluster/crds?ref=v2.3.4" | grep '"name"'
```

## 2. Install the AWS provider (family + EC2)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-family-aws
spec:
  package: xpkg.upbound.io/upbound/provider-family-aws:v1.19.0
---
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-aws-ec2
spec:
  package: xpkg.upbound.io/upbound/provider-aws-ec2:v1.19.0
EOF
```

Wait until both report `INSTALLED: True` and `HEALTHY: True`:

```bash
kubectl get providers.pkg.crossplane.io
```

## 3. Create AWS credentials secret + ProviderConfig

Credentials were sourced from the local `~/.aws/credentials` file (`[default]`
profile) and loaded straight into a Kubernetes secret without ever being typed or
displayed — swap the `--from-file` source if you keep credentials elsewhere.

```bash
kubectl create secret generic aws-creds -n crossplane-system \
  --from-file=creds=$HOME/.aws/credentials
```

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: aws.upbound.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: Secret
    secretRef:
      namespace: crossplane-system
      name: aws-creds
      key: creds
EOF
```

## 4. Apply the EC2 + networking manifest

```bash
kubectl apply -f ec2-instances-crossplane.yaml
```

This creates, in order: `VPC` → `InternetGateway` → `Subnet` → `RouteTable` →
`Route` (default route to the IGW — a separate resource from `RouteTable` in this
provider version) → `RouteTableAssociation` → `SecurityGroup` + 2
`SecurityGroupRule`s (SSH ingress restricted to one IP, all-traffic egress) →
`KeyPair` (imported from local `~/.ssh/id_rsa.pub`) → 2 `Instance`s.

Check status:

```bash
kubectl get managed
```

Get public IPs:

```bash
kubectl get instance.ec2.aws.upbound.io \
  -o custom-columns='NAME:.metadata.name,ID:.status.atProvider.id,PUBLIC-IP:.status.atProvider.publicIp,KEY:.status.atProvider.keyName'
```

SSH in:

```bash
ssh -i ~/.ssh/id_rsa ec2-user@<PUBLIC-IP>
```

### Notes / gotchas

- **AMI ID**: `ami-07a5b367e8dc8bd92` is a snapshot of the latest Amazon Linux 2023
  AMI for `us-east-1` at the time this was set up — it rotates periodically. Refresh
  with:
  ```bash
  aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --region us-east-1 --query 'Parameters[0].Value' --output text
  ```
- **SSH ingress CIDR**: locked to a single IP (`23.124.147.21/32`, detected via
  `curl -s https://ifconfig.me`) in the manifest's `demo-sg-rule-ssh-ingress`
  resource. If your public IP changes, update that CIDR and re-apply, or you'll be
  locked out.
- **Key pair is launch-only**: AWS does not allow attaching/changing a key pair on
  an already-running instance. If you ever change `keyName` in the manifest, the
  provider will refuse the in-place update — you must delete and let Crossplane
  recreate the `Instance` resources (new instance IDs and IPs result):
  ```bash
  kubectl delete instance.ec2.aws.upbound.io instance-1 instance-2
  kubectl apply -f ec2-instances-crossplane.yaml
  ```

## 5. Tear everything down

Deletes the EC2 instances, key pair, security group/rules, routing, subnet, IGW,
and VPC — all real AWS resources, billing stops once this completes:

```bash
kubectl delete -f ec2-instances-crossplane.yaml
```

Verify everything is gone:

```bash
kubectl get managed
```

Remove the AWS provider and family (optional — leave installed if you'll use
Crossplane for AWS again):

```bash
kubectl delete provider.pkg.crossplane.io provider-aws-ec2 provider-family-aws
```

Remove the ProviderConfig and credentials secret (optional):

```bash
kubectl delete providerconfig.aws.upbound.io default
kubectl delete secret aws-creds -n crossplane-system
```

The core Crossplane CRD fixes from step 1 and Crossplane itself were pre-existing
cluster infrastructure — no need to remove those as part of tearing this down.
