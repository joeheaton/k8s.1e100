# Deploy a K8S cluster on Google Kubernetes Engine

Uses Google Cloud [Cloud Foundation Fabric](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/)

## Config

Copy `cluster.example.yaml` to `cluster.yaml`, disable features by setting to empty (`{}` or `[]`) or `false`.

## Prepare

Clone Clound Foundation Fabric Terraform modules:

```shell
git clone --depth 1 --branch v21.0.0 https://github.com/GoogleCloudPlatform/cloud-foundation-fabric.git tf/fabric
```

Update modules:

```shell
git fetch --tags
git checkout tags/v21.0.0
```

## Deployment

```shell
cd tf/
terraform apply
```

First time only, migrate Terraform state to a remote bucket.

```shell
cat <<EOF > backend.tf
terraform {
  backend "gcs" {
    bucket = "$( terraform output -json | jq -r '."state_bucket".value' )"
    prefix = "terraform/state/bootstrap"
  }
}
EOF

tf init
```

Export helper variables locally:

```shell
REPO="$( git rev-parse --show-toplevel )"
TF_SUFFIX="$( cd ${REPO}/tf; terraform output -json | jq -r '.suffix.value' )"
CLUSTER_NAME="$( yq '.name' ${REPO}/cluster.yaml )-${TF_SUFFIX}"
PROJECT_ID="$( yq '.project' ${REPO}/cluster.yaml )"
REGION="$( yq '.region' ${REPO}/cluster.yaml )"
ZONE="$( yq '.zone' ${REPO}/cluster.yaml )"
BASTION="$( cd ${REPO}/tf; terraform output -json | jq -r '.iap_bastion_hostname.value' )"
```

## Bastion

Bastion nodes are required for kubectl to access a private cluster from outside the VPC network.

For example, if you use `kubectl` on your desktop, you will need to enable the `bastion` in the configuration and run the following commands on your local machine:

<https://cloud.google.com/kubernetes-engine/docs/tutorials/private-cluster-bastion>

```shell
gcloud container clusters get-credentials $CLUSTER_NAME --region=$REGION --project=$PROJECT_ID
gcloud compute ssh $BASTION --tunnel-through-iap --project=$PROJECT_ID --zone=$ZONE -- -4 -L8888:localhost:8888 -N -q -f
kubectl config set-cluster $( kubectl config current-context ) --proxy-url http://localhost:8888
```

To start a preempted bastion node run: `gcloud compute instances start bastion-vm --project $PROJECT_ID`

BASTION is output by Terraform under "iap_bastion_hostname".

## Interacting with Kubernetes

[Google Cloud - Install kubectl and configure cluster access](https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl)

```shell
gcloud container clusters get-credentials $CLUSTER_NAME --region=$REGION --project=$PROJECT_ID
kubectl get namespaces
```

## More

- [Autopilot](docs/autopilot.md)
- [Flux](docs/flux.md)
- [Cert Manager](docs/cert-manager.md)
- [MicroK8S](docs/microk8s.md)

## Versions

| Component / Tool | Version / Tag |
| ---       | ---     |
| Terraform | >= 1.3 |
| [Fabric modules](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/) | v21.0.0 |
