# GitOps via Flux

**GitOps** is the deployment model where infrastructure and applications are managed and configured via simple YAML in Git repo.

**Flux** is a Continuous Delivery platform for Kubernetes deployed using native Kubernetes resources.

## Install Flux CLI

```shell
curl -s https://fluxcd.io/install.sh | sudo bash
```

## Bootstrap Flux with monorepo

Create a repo dedicated to your Kubernetes cluster manifests.

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

[Create a GitHub PAT](https://github.com/settings/tokens) with the Repository Permissions:

- `Administration: Read/Write`
- `Contents: Read/Write`.

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
