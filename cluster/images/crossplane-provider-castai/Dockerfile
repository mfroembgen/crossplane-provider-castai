# The image Makefile passes this from .tool-versions. The default is only a
# fallback for builds that do not go through the Makefile.
ARG GO_VERSION=1.26.11

# Rebuild the Terraform CLI from its upstream release tag and the CAST AI
# provider plugin from the fork's pinned commit with a Go toolchain that carries
# the eMudhra CA distrust (CVE-2026-111943). Same build flags as upstream.
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine AS tf-builder

RUN apk --no-cache add git

ARG TARGETOS
ARG TARGETARCH
ARG TERRAFORM_VERSION
ARG TERRAFORM_PROVIDER_VERSION
ARG TERRAFORM_PROVIDER_DOWNLOAD_NAME
ARG TERRAFORM_NATIVE_PROVIDER_BINARY

ENV CGO_ENABLED=0
ENV GOFLAGS="-trimpath -buildvcs=false"
ENV GOOS=${TARGETOS}
ENV GOARCH=${TARGETARCH}

# Terraform CLI (MPL-2.0)
RUN git clone -c advice.detachedHead=false --depth 1 --branch "v${TERRAFORM_VERSION}" \
      https://github.com/hashicorp/terraform /src/terraform \
  && cd /src/terraform \
  && go build -ldflags "-s -w -X 'github.com/hashicorp/terraform/version.Version=${TERRAFORM_VERSION}' -X 'github.com/hashicorp/terraform/version.Prerelease='" \
       -o /out/terraform . \
  && install -D -m 0644 LICENSE /out/licenses/terraform/LICENSE

# CAST AI Terraform provider plugin (MIT), from the fork's pinned native HPA commit
ARG TERRAFORM_PROVIDER_REPO
ARG TERRAFORM_PROVIDER_COMMIT
RUN git init -q /src/provider \
  && cd /src/provider \
  && git fetch -q --depth 1 "${TERRAFORM_PROVIDER_REPO}" "${TERRAFORM_PROVIDER_COMMIT}" \
  && git checkout -q --detach FETCH_HEAD \
  && test "$(git rev-parse HEAD)" = "${TERRAFORM_PROVIDER_COMMIT}" \
  && go build -ldflags "-s -w -X main.version=${TERRAFORM_PROVIDER_VERSION} -X main.commit=${TERRAFORM_PROVIDER_COMMIT}" \
       -o "/out/${TERRAFORM_NATIVE_PROVIDER_BINARY}" . \
  && install -D -m 0644 LICENSE "/out/licenses/${TERRAFORM_PROVIDER_DOWNLOAD_NAME}/LICENSE"

FROM alpine:3.22.8
RUN apk --no-cache upgrade && apk --no-cache add ca-certificates bash

ARG TARGETOS
ARG TARGETARCH
ARG CROSSPLANE_PROVIDER_VERSION
ARG CROSSPLANE_PROVIDER_REVISION

LABEL org.opencontainers.image.source="https://github.com/mfroembgen/crossplane-provider-castai" \
      org.opencontainers.image.version="${CROSSPLANE_PROVIDER_VERSION}" \
      org.opencontainers.image.revision="${CROSSPLANE_PROVIDER_REVISION}"

ADD "bin/${TARGETOS}_${TARGETARCH}/provider" /usr/local/bin/provider

ENV USER_ID=65532
ENV CASTAI_ADDITIONAL_USER_AGENT crossplane-provider-castai/${CROSSPLANE_PROVIDER_VERSION}

# Setup Terraform environment

## Provider-dependent configuration
ARG TERRAFORM_VERSION
ARG TERRAFORM_PROVIDER_SOURCE
ARG TERRAFORM_PROVIDER_VERSION
ARG TERRAFORM_NATIVE_PROVIDER_BINARY

## End of - Provider-dependent configuration

ENV PLUGIN_DIR /terraform/provider-mirror/registry.terraform.io/${TERRAFORM_PROVIDER_SOURCE}/${TERRAFORM_PROVIDER_VERSION}/${TARGETOS}_${TARGETARCH}
ENV TF_CLI_CONFIG_FILE /terraform/.terraformrc
ENV TF_FORK 0

COPY --from=tf-builder /out/terraform /usr/local/bin/terraform
COPY --from=tf-builder "/out/${TERRAFORM_NATIVE_PROVIDER_BINARY}" "${PLUGIN_DIR}/${TERRAFORM_NATIVE_PROVIDER_BINARY}"
COPY --from=tf-builder /out/licenses /usr/local/share/licenses
ADD terraformrc.hcl ${TF_CLI_CONFIG_FILE}

RUN chmod +x /usr/local/bin/terraform ${PLUGIN_DIR}/* \
  && chown -R ${USER_ID}:${USER_ID} /terraform
# End of - Setup Terraform environment

# Provider controller needs these environment variable at runtime
ENV TERRAFORM_VERSION ${TERRAFORM_VERSION}
ENV TERRAFORM_PROVIDER_SOURCE ${TERRAFORM_PROVIDER_SOURCE}
ENV TERRAFORM_PROVIDER_VERSION ${TERRAFORM_PROVIDER_VERSION}
ENV TERRAFORM_NATIVE_PROVIDER_PATH ${PLUGIN_DIR}/${TERRAFORM_NATIVE_PROVIDER_BINARY}

USER ${USER_ID}
EXPOSE 8080

ENTRYPOINT ["provider"]
