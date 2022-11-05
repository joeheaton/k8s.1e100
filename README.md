# Deploy a K8S cluster on Google Kubernetes Engine

Uses Google Cloud [Cloud Foundation Fabric](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/)

## Config

Copy `cluster.example.yaml` to `cluster.yaml`

Setting `autopilot` to true sets/overrides settings that are required for a GKE Autopilot cluster.

## Deploy

Deploy the cluster

```shell
cd tf/
terraform init
terraform apply
```

Environment variables required for `gcloud` and proxying `kubectl`:

```shell
export CLUSTER_NAME="$( yq eval '.name' cluster.yaml )-$( cd tf/; terraform output -json | jq -r '.suffix.value' )" \
PROJECT_ID="$( yq eval '.project' cluster.yaml )" \
ZONE="$( yq eval '.zone' cluster.yaml )" \
REGION="$( yq eval '.region' cluster.yaml )"
```

## Bastion

Bastion nodes are required for kubectl to access a private cluster from outside the VPC network.

For example, if you use `kubectl` on your desktop, you will need to enable the `bastion` in the configuration and run the following commands on your local machine:

https://cloud.google.com/kubernetes-engine/docs/tutorials/private-cluster-bastion

```shell
gcloud container clusters get-credentials $CLUSTER_NAME --region=$REGION --project=$PROJECT_ID
gcloud compute ssh bastion-vm --tunnel-through-iap --project=$PROJECT_ID --zone=$ZONE -- -4 -L8888:localhost:8888 -N -q -f
HTTPS_PROXY=localhost:8888 kubectl get ns
```

INSTANCE_NAME is output by Terraform under "iap_bastion_hostname".
