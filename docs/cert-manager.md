# Cert Manager

## HTTPS/X.509 certificates

Go to Cloudflare [API Tokens](https://dash.cloudflare.com/profile/api-tokens) and generate a token with `Zone.DNS` permissions.

```shell
kubectl -n cert-manager create secret generic cloudflare-apikey-secret --from-literal="apikey=CLOUDFLARE_KEY"
```
