# Provider crossplane-provider-castai

`crossplane-provider-castai` is a [Crossplane](https://crossplane.io/) provider that
is built using [Upjet](https://github.com/crossplane/upjet) code
generation tools and exposes XRM-conformant managed resources for the
CastAI API.

This fork preserves native HPA settings and embeds the matching
[Terraform provider fork](https://github.com/mfroembgen/terraform-provider-castai).

## Getting Started

Install the provider by using the following command after changing the image tag
to the [latest release](https://github.com/mfroembgen/crossplane-provider-castai/releases):
```
up ctp provider install ghcr.io/mfroembgen/crossplane-provider-castai-api-parity:v0.42.0
```

Alternatively, you can use declarative installation:
```
cat <<EOF | kubectl apply -f -
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: crossplane-provider-castai
spec:
  package: ghcr.io/mfroembgen/crossplane-provider-castai-api-parity:v0.42.0
EOF
```

To run the provider with debug logging, create a `DeploymentRuntimeConfig` and
reference it from the `Provider` via `spec.runtimeConfigRef`:
```
cat <<EOF | kubectl apply -f -
apiVersion: pkg.crossplane.io/v1beta1
kind: DeploymentRuntimeConfig
metadata:
  name: debug-config
spec:
  deploymentTemplate:
    spec:
      selector: {}
      template:
        spec:
          containers:
            - name: package-runtime
              args:
                - --debug
---
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: crossplane-provider-castai
spec:
  package: ghcr.io/mfroembgen/crossplane-provider-castai-api-parity:v0.42.0
  runtimeConfigRef:
    name: debug-config
EOF
```

The [upstream API reference](https://doc.crds.dev/github.com/crossplane-contrib/crossplane-provider-castai)
covers the shared resources. See the [ScalingPolicy CRD](package/crds/castai.upbound.io_scalingpolicies.yaml)
for this fork's native HPA fields.

## Developing

Install the tools pinned in `mise.toml` with `mise install`. Generation needs
`goimports` on `PATH`, as configured in CI.

Update the submodules, such as the common build scripts:
```console
make submodules
```

Run the complete code-generation pipeline:
```console
make generate
```

Run against a Kubernetes cluster:

```console
make run
```

Build packages:

```console
make all
```

Build binary:

```console
make build
```

### Updating to a New Terraform Provider Version

To update the embedded [Terraform provider fork](https://github.com/mfroembgen/terraform-provider-castai):

1. Set `TERRAFORM_PROVIDER_VERSION` to the upstream release the fork is based
   on and `TERRAFORM_PROVIDER_COMMIT` to the fork commit carrying its patches
   in `Makefile`. Generation and the image build compile the provider from that
   commit, the image with the Go version in `.tool-versions`.
2. Run `make submodules` once, then `make generate`. This builds the provider,
   extracts its schema, pulls the documentation, transforms Plugin
   Framework attributes for Upjet v1, and regenerates the Go API and CRDs.
3. Run `make vendor vendor.check reviewable` and inspect changes to existing API
   fields before publishing. The native HPA serialization test must pass.
4. If exposing a new Terraform resource, add its external name in
   `config/external_name.go`, create its configuration package, and register it
   in `config/provider.go` before regenerating.

CI builds and checks both Linux packages without a Kubernetes deployment.
After review, dispatch CI with `publish=true` to publish the checked packages.
Publication refuses an existing version; keep upstream tags on upstream commits
and record the patched source commit and package digest in the fork release.

## Report a Bug

For filing bugs, suggesting improvements, or requesting new features, please
open an [issue](https://github.com/crossplane-contrib/crossplane-provider-castai/issues).
