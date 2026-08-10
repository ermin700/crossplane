# Crossplane GCP Compute Setup — GKE Cluster (Ambient Node Credentials)

Steps to provision a VPC network, subnetwork, firewall rules, and two Compute Engine
instances via Crossplane, running on the GKE cluster provisioned by
[`terraform/`](terraform/).

> **No Workload Identity here.** This is running against a locked-down
> training-sandbox project (`playground-s-11-1fc9fa68`) where `setIamPolicy` is
> denied for every available identity, so no IAM binding — including a Workload
> Identity binding — can ever be created. Instead, the provider pod authenticates as
> the GKE node's **default Compute Engine service account**, which the lab platform
> pre-grants `roles/editor`. That's broader-privileged than the scoped-SA design this
> repo would otherwise use; see the note at the top of `terraform/iam.tf`. Restore
> per-provider dedicated SAs + Workload Identity if you ever run this against a
> project where you can grant IAM roles.

Manifest: `gce-instances-crossplane.yaml` (same directory as this file).

## 0. Prerequisites

- The `terraform/` stack has been applied (`terraform apply`) — this creates the GKE
  cluster (no `workload_identity_config`, nodes use the default Compute Engine SA)
  and installs Crossplane via Helm.
- kubectl configured against the GKE cluster:
  ```bash
  terraform output -raw kubeconfig_command | bash
  kubectl get pods -n crossplane-system
  ```
- Core Crossplane CRDs are present out of the box on a fresh Helm install — no manual
  CRD fixes needed here (unlike the rke2 cluster in the AWS doc).

## 1. Install the GCP provider (family + Compute)

No `DeploymentRuntimeConfig` needed — every pod on these nodes already has ambient
access to the default Compute Engine SA via the metadata server, regardless of which
KSA it runs under.

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-family-gcp
spec:
  package: xpkg.upbound.io/upbound/provider-family-gcp:v3.0.0
---
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-gcp-compute
spec:
  package: xpkg.upbound.io/upbound/provider-gcp-compute:v3.0.0
EOF
```

Wait until both report `INSTALLED: True` and `HEALTHY: True`:

```bash
kubectl get providers.pkg.crossplane.io
```

## 2. Create the ProviderConfig (InjectedIdentity, no key file)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gcp.upbound.io/v1beta1
kind: ProviderConfig
metadata:
  name: default-gcp
spec:
  projectID: playground-s-11-1fc9fa68
  credentials:
    source: InjectedIdentity
EOF
```

## 3. Apply the network + instances manifest

```bash
kubectl apply -f gce-instances-crossplane.yaml
```

This creates, in order: `Network` (custom-mode VPC) → `Subnetwork`
(`10.10.1.0/24` in `us-central1`) → 2 `Firewall`s (SSH ingress restricted to one IP,
all-traffic egress, both scoped to the `demo-gcp` network tag) → 1 `Instance`
(`e2-micro`, Debian 12, with an ephemeral external IP and an SSH key injected via
instance metadata — kept to a single `e2-micro` since that's GCP's entire
always-free Compute Engine allowance; anything more or larger is billed).

Check status:

```bash
kubectl get managed
```

Get external IPs:

```bash
kubectl get instance.compute.gcp.upbound.io \
  -o custom-columns='NAME:.metadata.name,ZONE:.spec.forProvider.zone,STATUS:.status.atProvider.currentStatus'

kubectl get instance.compute.gcp.upbound.io gce-instance-1 \
  -o jsonpath='{.status.atProvider.networkInterface[0].accessConfig[0].natIp}'
```

SSH in:

```bash
ssh -i ~/.ssh/id_rsa ermin@<EXTERNAL-IP>
```

### Notes / gotchas

- **Why `InjectedIdentity` works without any binding step here**: without Workload
  Identity, GKE pods reach the node's metadata server directly and get back the
  node's attached service account's token — no per-KSA binding required, because
  every pod on the node is trusted equally. This is exactly the behavior Workload
  Identity exists to lock down; it's acceptable here only because the sandbox leaves
  no other option and there's nothing sensitive on this project.
- **Image**: `debian-cloud/debian-12` is the public Debian 12 image family — GCP
  always resolves it to the latest image in that family at create time.
- **SSH ingress CIDR**: locked to a single IP (`23.124.147.21/32`) in the manifest's
  `demo-gcp-fw-ssh-ingress` resource. If your public IP changes, update that CIDR and
  re-apply, or you'll be locked out.
- **`projectID` on the ProviderConfig**: GCP resources in this manifest don't take a
  per-resource project field — they inherit it from `ProviderConfig.spec.projectID`.
- **Both `bootDisk` and `accessConfig` are lists** (mirroring the underlying
  Terraform-generated schema) even though each instance only ever has one boot disk
  and one access config — leave them as single-element lists.

## 4. Tear everything down

Deletes the instances, firewall rules, subnetwork, and network — all real GCP
resources, billing stops once this completes:

```bash
kubectl delete -f gce-instances-crossplane.yaml
```

Verify everything is gone:

```bash
kubectl get managed
```

Remove the GCP provider and family (optional — leave installed if you'll use
Crossplane for GCP again):

```bash
kubectl delete provider.pkg.crossplane.io provider-gcp-compute provider-family-gcp
```

Remove the ProviderConfig (optional):

```bash
kubectl delete providerconfig.gcp.upbound.io default-gcp
```

No credentials secret to clean up — `InjectedIdentity` never created one.
