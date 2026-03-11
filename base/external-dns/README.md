# External-DNS

## What it does

[external-dns](https://github.com/kubernetes-sigs/external-dns) is a Kubernetes add-on that automatically manages DNS records in an external DNS provider based on Kubernetes `Ingress` and `Service` resources. It reads `external-dns.alpha.kubernetes.io/hostname` annotations and creates or updates the corresponding DNS records.

This cluster is configured to use a BIND DNS server as the backend, authenticated with a TSIG key.

## Why it was added

All cluster services are exposed via Traefik ingresses. external-dns ensures that DNS records for those services are automatically created and kept in sync with the cluster state, removing the need to manually manage DNS.

## Dependencies

None — external-dns has no dependencies on other components in this repository (though it does require a reachable external BIND DNS server configured via `EXTERNAL_DNS_BINDSERVER_IP`).

## Dependents

No other components in this repository depend on external-dns directly. However, every service exposed via an ingress annotation relies on external-dns to create its DNS record.

## User Guide

### How DNS records are created

Annotate any `Ingress` or `IngressRoute` with:

```yaml
annotations:
  external-dns.alpha.kubernetes.io/hostname: myservice.example.com
```

external-dns will reconcile this and create/update the DNS record automatically.

### Checking external-dns logs

```bash
kubectl -n <external-dns-namespace> logs -l app.kubernetes.io/name=external-dns --tail=50
```

### TSIG secret rotation

The TSIG key used to authenticate to the BIND server is stored in a Kubernetes `Secret` (`externalDnsTsigSecret.yaml`). If the TSIG key is rotated:

1. Update the `Secret` in the cluster.
2. external-dns will pick up the new key automatically via Reloader (if annotated) or after a manual pod restart.

### Domain filters

external-dns only manages DNS records for domains listed in `EXTERNAL_DNS_DOMAIN_FILTERS`. Records for other domains are ignored.
