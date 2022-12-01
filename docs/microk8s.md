# MicroK8S

Local rapid development can be achieved in MicroK8S, the following command enables a similar featureset as GKE:

```shell
sudo snap remove microk8s  # `microk8s reset` does not seem to work fully
sudo snap install microk8s --classic
echo dashboard istio | xargs -n1 microk8s disable
echo dns hostpath-storage metrics-server prometheus | xargs -n1 microk8s enable
microk8s start
alias mk="microk8s kubectl"
mk get ns
```

We need to generate a config file for flux to deploy to MicroK8S:

```shell
microk8s config > ${TMPDIR}/microk8s.kubeconfig
flux bootstrap git --url=ssh://git@github.com/joeheaton/k8s.1e100 --branch=main --path=config/clusters/dev --kubeconfig ${TMPDIR}/microk8s.kubeconfig
```
