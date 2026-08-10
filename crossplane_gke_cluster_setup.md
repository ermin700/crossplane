# Crossplane GKE Cluster Provisioning — GKE Cluster (Ambient Node Credentials)

Steps to provision a **new, separate 3-node GKE cluster** via Crossplane, running on
the terraform/-provisioned control-plane GKE cluster, using `provider-gcp-container`.
Same pattern as [`crossplane_gcp_setup.md`](crossplane_gcp_setup.md) (Compute Engine
instances).

> **No Workload Identity here.** This is running against a locked-down
> training-sandbox project (`playground-s-11-1fc9fa68`) where `setIamPolicy` is
> denied for every available identity — no IAM binding, dedicated SA, or Workload
> Identity binding can be created. The provider pod authenticates as the GKE node's
> default Compute Engine service account instead, which the lab platform pre-grants
> `roles/editor` — more than enough for `roles/container.admin`-level operations, just
> broader than that scoped role would be. See the note at the top of
> `terraform/iam.tf`.

Manifest: `gke-cluster-crossplane.yaml` (same directory as this file).

## 0. Prerequisites

- The `terraform/` stack has been applied.
- kubectl configured against the **control-plane GKE cluster** (not the rke2 cluster
  used for the AWS/EC2 setup):
  ```bash
  terraform output -raw kubeconfig_command | bash
  kubectl config current-context
  ```

## 1. Install the GCP provider (family + Container)

No `DeploymentRuntimeConfig` needed — the provider pod gets ambient access to the
node's default Compute Engine SA regardless of which KSA it runs under.

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
  name: provider-gcp-container
spec:
  package: xpkg.upbound.io/upbound/provider-gcp-container:v3.0.0
EOF
```

If `provider-family-gcp` is already installed (e.g. from the Compute setup), leave it
alone — installing the same package twice is a no-op.

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
  name: default-gcp-container
spec:
  projectID: playground-s-11-1fc9fa68
  credentials:
    source: InjectedIdentity
EOF
```

## 3. Apply the cluster manifest

```bash
kubectl apply -f gke-cluster-crossplane.yaml
```

This creates, in order: `Cluster` (zonal, `us-central1-a`, default VPC-native
networking on the project's default network, `initialNodeCount: 1` then
`removeDefaultNodePool: true` so the default pool is torn down) → `NodePool`
(3 × `e2-medium`, `pd-standard` 50GB disks, auto-repair + auto-upgrade).

GKE cluster creation takes several minutes. Check status:

```bash
kubectl get managed
kubectl describe cluster.container.gcp.upbound.io demo-gke-cluster
```

Get the new cluster's kubeconfig once ready:

```bash
gcloud container clusters get-credentials demo-gke-cluster \
  --zone us-central1-a --project playground-s-11-1fc9fa68
```

### Notes / gotchas

- **Why `InjectedIdentity` works without any binding step here**: without Workload
  Identity, GKE pods reach the node's metadata server directly and get back the
  node's attached service account's token — no per-KSA binding required. This is
  exactly the behavior Workload Identity exists to lock down; it's acceptable here
  only because the sandbox leaves no other option.
- **`removeDefaultNodePool: true` + a separate `NodePool` resource**: GKE always
  creates a default node pool alongside the cluster. Setting
  `initialNodeCount: 1` + `removeDefaultNodePool: true` deletes that default pool
  right after creation so only the explicit `NodePool` resource's 3 nodes remain —
  same pattern `gke.tf` uses in the control-plane cluster itself.
- **Zonal, not regional**: `location: us-central1-a` (a zone) means a single-zone
  control plane and node pool — 3 nodes all in one zone. For multi-zone HA, set
  `location` to a region (e.g. `us-central1`) instead; NodePool's `nodeCount` then
  means *per zone*, so you'd want `nodeCount: 1` for 3 nodes total across 3 zones.
- **Default network**: no `networkSelector`/`subnetworkSelector` — this relies on the
  project's default VPC/subnet existing with auto-created subnets. If your project has
  the default network deleted or firewalled down, this will fail; point it at the
  `demo-gcp-vpc`/`demo-gcp-subnet` from `gce-instances-crossplane.yaml` instead (via
  `networkSelector`/`subnetworkSelector` matching `app: demo-gcp`) if you'd rather use
  a dedicated VPC.
- **`deletionProtection: false`**: GKE clusters default to deletion protection in
  recent API versions, which blocks `kubectl delete`. Set to `true` once this is a
  cluster you don't want accidentally torn down.
- **Real cost warning**: this creates a second, separate 3-node GKE cluster (on top of
  the control-plane cluster `terraform/` already provisions) — real billing, and in a
  lab sandbox, real risk of hitting quota or the lab's time/resource limits. Tear it
  down when you're done experimenting with it.

## 4. Tear everything down

```bash
kubectl delete -f gke-cluster-crossplane.yaml
```

This deletes the `NodePool` first, then the `Cluster` — all real GCP resources,
billing stops once this completes. If `deletionProtection` was flipped to `true`,
patch it back to `false` first or the delete will hang.

Verify:

```bash
kubectl get managed
```

Remove the provider and family (optional):

```bash
kubectl delete provider.pkg.crossplane.io provider-gcp-container
```

Leave `provider-family-gcp` installed if `provider-gcp-compute` still depends on it.

Remove the ProviderConfig (optional):

```bash
kubectl delete providerconfig.gcp.upbound.io default-gcp-container
```
