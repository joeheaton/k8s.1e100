# GKE Autopilot

## Considerations

### Default Resource Requests

https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests#defaults

> General-purpose
> CPU: 0.5vCPU
> Memory: 2GiB

Autopilot will ignore any resource requests/limits below the above values.
