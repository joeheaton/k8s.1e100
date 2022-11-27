# Deploy a K8S cluster on Google Kubernetes Engine

Uses Google Cloud [Cloud Foundation Fabric](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/)

## Config

Copy `cluster.example.yaml` to `cluster.yaml`, disable features by setting to empty (`{}` or `[]`) or `false`.

## Prepare

```shell
git clone --depth 1 --branch daily-2022.11.11 https://github.com/GoogleCloudPlatform/cloud-foundation-fabric.git tf/fabric
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

BASTION is output by Terraform under "iap_bastion_hostname".

## Interacting with Kubernetes

[Google Cloud - Install kubectl and configure cluster access](https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl)

```shell
gcloud container clusters get-credentials $CLUSTER_NAME --region=$REGION --project=$PROJECT_ID
kubectl get namespaces
```

## GitOps via Flux

**GitOps** is the deployment model where infrastructure and applications are managed and configured via simple YAML in Git repo.

**Flux** is a Continuous Delivery platform for Kubernetes deployed using native Kubernetes resources.

### Install Flux CLI

```shell
curl -s https://fluxcd.io/install.sh | sudo bash
```

## Bootstrap Flux with monorepo

[Flux installation docs](https://fluxcd.io/flux/installation/)

### Bootstrap with Git

```shell
flux bootstrap git \
  --url=ssh://git@GIT_HOST:GIT_USER/GIT_REPO
  --branch=GIT_BRANCH
  --path=PATH_TO_CONFIG
```

Example:

```shell
flux bootstrap git --url=ssh://git@github.com/joeheaton/k8s.1e100 --branch=main --path=config/clusters/dev
```

### Bootstrap with GitHub

Flux bootstrap supports GitHub PAT (Personal Access Tokens), this example uses the [GitHub CLI](https://github.com/cli/cli#installation) to add Flux-generated deploy keys.

[Create a GitHub PAT](https://github.com/settings/tokens).

```shell

flux bootstrap github \
  --owner joeheaton \
  --repository k8s.1e100 \
  --branch cluster-dev \
  --path ./config/clusters/dev/ \
  --personal

# Login to GitHub.com via Web Browser
gh auth login -p ssh -h github.com -w

# Send the key to gh
echo KEY_GENERATED_BY_FLUX | gh repo deploy-key add -t Test -
```

### Update Flux-system

To update Flux-system, run: `flux reconcile source git flux-system`.

### Flux chat notifications

Flux can push messages to a chat webhook, Flux supports multiple chat providers: <https://fluxcd.io/flux/guides/notifications/>

To enable notifications first we create a secret containing the webhook URL:

```shell
kubectl -n flux-system create secret generic flux-notify-webhook --from-literal="address=https://WEBHOOK_URL"
```

Configure the chat provider in `config/clusters/*/flux-notifications/release.yaml` by replacing `googlechat` with your provider.

## HTTPS/X.509 certificates

Go to Cloudflare [API Tokens](https://dash.cloudflare.com/profile/api-tokens) and generate a token with `Zone.DNS` permissions.

```shell
kubectl -n cert-manager create secret generic cloudflare-apikey-secret --from-literal="apikey=CLOUDFLARE_KEY"
```

## Versions

| Component / Tool | Version / Tag |
| ---       | ---     |
| Terraform | >= 1.3 |
| [Fabric modules](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/) | daily-2022.11.11 |
