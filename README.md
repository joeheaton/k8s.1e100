# Deploy a K8S cluster on Google Kubernetes Engine

Uses Google Cloud [Cloud Foundation Fabric](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/)

## Config

Copy `cluster.example.yaml` to `cluster.yaml`

Setting `autopilot` to true sets/overrides settings that are required for a GKE Autopilot cluster.

## Deployment

```shell
cd tf/
terraform apply
```

Export helper variables locally:

```shell
TF_SUFFIX="$( terraform output -json | jq -r '.suffix.value' )"
CLUSTER_NAME="$( yq '.name' ../cluster.yaml )-${TF_SUFFIX}"
PROJECT_ID="$( yq '.project' ../cluster.yaml )"
REGION="$( yq '.region' ../cluster.yaml )"
ZONE="$( yq '.zone' ../cluster.yaml )"
BASTION="$( terraform output -json | jq -r '.iap_bastion_hostname.value' )"
```

Install Flux CD CLI:

```shell
curl -s https://fluxcd.io/install.sh | sudo bash
```

Provision Flux CD:

[Flux installation docs](https://fluxcd.io/flux/installation/)

```shell
flux bootstrap github \
  --owner=GITHUB_OWNER \
  --repository=GITHUB_REPO_NAME \
  --path=PATH_TO_CONFIGSYNC \
  --personal
```

## Bastion

Bastion nodes are required for kubectl to access a private cluster from outside the VPC network.

For example, if you use `kubectl` on your desktop, you will need to enable the `bastion` in the configuration and run the following commands on your local machine:

https://cloud.google.com/kubernetes-engine/docs/tutorials/private-cluster-bastion

```shell
gcloud container clusters get-credentials $CLUSTER_NAME --region=$REGION --project=$PROJECT_ID
gcloud compute ssh $BASTION --tunnel-through-iap --project=$PROJECT_ID --zone=$ZONE -- -4 -L8888:localhost:8888 -N -q -f
HTTPS_PROXY=localhost:8888 kubectl get ns
```

BASTION is output by Terraform under "iap_bastion_hostname".

