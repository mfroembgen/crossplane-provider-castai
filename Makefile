# ====================================================================================
# Setup Project

PROJECT_NAME ?= crossplane-provider-castai
PROJECT_REPO ?= github.com/crossplane-contrib/$(PROJECT_NAME)

export TERRAFORM_VERSION ?= 1.5.7

export TERRAFORM_PROVIDER_SOURCE ?= castai/castai
export TERRAFORM_PROVIDER_REPO ?= https://github.com/mfroembgen/terraform-provider-castai
export TERRAFORM_PROVIDER_VERSION ?= 9.23.0
export TERRAFORM_PROVIDER_COMMIT ?= d6c0835a1fcc0ff65ae75574acc60b6403b7d66d
export TERRAFORM_PROVIDER_DOWNLOAD_NAME ?= terraform-provider-castai
export TERRAFORM_NATIVE_PROVIDER_BINARY ?= terraform-provider-castai_v$(TERRAFORM_PROVIDER_VERSION)
export TERRAFORM_DOCS_PATH ?= docs/resources


PLATFORMS ?= linux_amd64 linux_arm64

# -include will silently skip missing files, which allows us
# to load those files with a target in the Makefile. If only
# "include" was used, the make command would fail and refuse
# to run a target until the include commands succeeded.
-include build/makelib/common.mk

# ====================================================================================
# Setup Output

-include build/makelib/output.mk

# ====================================================================================
# Setup Go

# Set a sane default so that the nprocs calculation below is less noisy on the initial
# loading of this file
NPROCS ?= 1

# each of our test suites starts a kube-apiserver and running many test suites in
# parallel can lead to high CPU utilization. by default we reduce the parallelism
# to half the number of CPU cores.
GO_TEST_PARALLEL := $(shell echo $$(( $(NPROCS) / 2 )))

# GOLANGCILINT_VERSION is inherited from build submodule by default.
# Uncomment below if you need to override the version.
GOLANGCILINT_VERSION ?= 2.12.2

GO_REQUIRED_VERSION ?= 1.20
GO_STATIC_PACKAGES = $(GO_PROJECT)/cmd/provider $(GO_PROJECT)/cmd/generator
GO_LDFLAGS += -X $(GO_PROJECT)/internal/version.Version=$(VERSION)
GO_SUBDIRS += cmd internal apis config
-include build/makelib/golang.mk

# ====================================================================================
# Setup Kubernetes tools

KIND_VERSION = v0.27.0
UP_VERSION = v0.38.4
UP_CHANNEL = stable
UPTEST_VERSION = v1.3.0
-include build/makelib/k8s_tools.mk

# ====================================================================================
# Setup Images

REGISTRY_ORGS ?= xpkg.upbound.io/crossplane-contrib
IMAGES = $(PROJECT_NAME)
-include build/makelib/imagelight.mk

# ====================================================================================
# Setup XPKG

XPKG_REG_ORGS ?= xpkg.upbound.io/crossplane-contrib
# NOTE(hasheddan): skip promoting on xpkg.upbound.io as channel tags are
# inferred.
XPKG_REG_ORGS_NO_PROMOTE ?= xpkg.upbound.io/crossplane-contrib
XPKGS = $(PROJECT_NAME)
-include build/makelib/xpkg.mk

# ====================================================================================
# Fallthrough

# run `make help` to see the targets and options

# We want submodules to be set up the first time `make` is run.
# We manage the build/ folder and its Makefiles as a submodule.
# The first time `make` is run, the includes of build/*.mk files will
# all fail, and this target will be run. The next time, the default as defined
# by the includes will be run instead.
fallthrough: submodules
	@echo Initial setup complete. Running make again . . .
	@make

# NOTE(hasheddan): we force image building to happen prior to xpkg build so that
# we ensure image is present in daemon.
xpkg.build.crossplane-provider-castai: do.build.images

# NOTE(hasheddan): we ensure up is installed prior to running platform-specific
# build steps in parallel to avoid encountering an installation race condition.
build.init: $(UP)

# ====================================================================================
# Setup Terraform for fetching provider schema
TERRAFORM := $(TOOLS_HOST_DIR)/terraform-$(TERRAFORM_VERSION)
TERRAFORM_WORKDIR := $(WORK_DIR)/terraform
TERRAFORM_PROVIDER_SCHEMA := config/schema.json
TERRAFORM_PROVIDER_SRC := $(WORK_DIR)/$(TERRAFORM_PROVIDER_SOURCE)
TERRAFORM_PROVIDER_MIRROR := $(WORK_DIR)/provider-mirror/registry.terraform.io/$(TERRAFORM_PROVIDER_SOURCE)/$(TERRAFORM_PROVIDER_VERSION)/$(SAFEHOST_PLATFORM)

$(TERRAFORM):
	@$(INFO) installing terraform $(HOSTOS)-$(HOSTARCH)
	@mkdir -p $(TOOLS_HOST_DIR)/tmp-terraform
	@curl -fsSL https://releases.hashicorp.com/terraform/$(TERRAFORM_VERSION)/terraform_$(TERRAFORM_VERSION)_$(SAFEHOST_PLATFORM).zip -o $(TOOLS_HOST_DIR)/tmp-terraform/terraform.zip
	@unzip $(TOOLS_HOST_DIR)/tmp-terraform/terraform.zip -d $(TOOLS_HOST_DIR)/tmp-terraform
	@mv $(TOOLS_HOST_DIR)/tmp-terraform/terraform $(TERRAFORM)
	@rm -fr $(TOOLS_HOST_DIR)/tmp-terraform
	@$(OK) installing terraform $(HOSTOS)-$(HOSTARCH)

$(TERRAFORM_PROVIDER_SCHEMA): $(TERRAFORM) pull-provider
	@$(INFO) generating provider schema for $(TERRAFORM_PROVIDER_SOURCE) $(TERRAFORM_PROVIDER_VERSION)
	@mkdir -p $(TERRAFORM_WORKDIR) $(TERRAFORM_PROVIDER_MIRROR)
	@CGO_ENABLED=0 GOOS=$(HOSTOS) GOARCH=$(SAFEHOSTARCH) $(GO) -C $(TERRAFORM_PROVIDER_SRC) build -trimpath -o $(TERRAFORM_PROVIDER_MIRROR)/$(TERRAFORM_NATIVE_PROVIDER_BINARY) .
	@printf 'provider_installation {\n  filesystem_mirror {\n    path = "$(WORK_DIR)/provider-mirror"\n  }\n}\n' > $(TERRAFORM_WORKDIR)/terraformrc.hcl
	@echo '{"terraform":[{"required_providers":[{"provider":{"source":"'"$(TERRAFORM_PROVIDER_SOURCE)"'","version":"'"$(TERRAFORM_PROVIDER_VERSION)"'"}}],"required_version":"'"$(TERRAFORM_VERSION)"'"}]}' > $(TERRAFORM_WORKDIR)/main.tf.json
	@rm -f $(TERRAFORM_WORKDIR)/.terraform.lock.hcl
	@TF_CLI_CONFIG_FILE=$(TERRAFORM_WORKDIR)/terraformrc.hcl $(TERRAFORM) -chdir=$(TERRAFORM_WORKDIR) init -upgrade > $(TERRAFORM_WORKDIR)/terraform-logs.txt 2>&1
	@TF_CLI_CONFIG_FILE=$(TERRAFORM_WORKDIR)/terraformrc.hcl $(TERRAFORM) -chdir=$(TERRAFORM_WORKDIR) providers schema -json=true > $(TERRAFORM_PROVIDER_SCHEMA) 2>> $(TERRAFORM_WORKDIR)/terraform-logs.txt
	@$(OK) generating provider schema for $(TERRAFORM_PROVIDER_SOURCE) $(TERRAFORM_PROVIDER_VERSION)

# The schema, the docs and the image's provider binary all come from this
# pinned commit of the Terraform provider fork.
pull-provider:
	@if [ ! -d "$(TERRAFORM_PROVIDER_SRC)/.git" ]; then \
		git init -q "$(TERRAFORM_PROVIDER_SRC)"; \
	fi
	@git -C "$(TERRAFORM_PROVIDER_SRC)" fetch --depth 1 "$(TERRAFORM_PROVIDER_REPO)" "$(TERRAFORM_PROVIDER_COMMIT)"
	@git -C "$(TERRAFORM_PROVIDER_SRC)" checkout -q --detach FETCH_HEAD
	@git -C "$(TERRAFORM_PROVIDER_SRC)" sparse-checkout disable
	@test "$$(git -C "$(TERRAFORM_PROVIDER_SRC)" rev-parse HEAD)" = "$(TERRAFORM_PROVIDER_COMMIT)"

generate.init: $(TERRAFORM_PROVIDER_SCHEMA)
	@$(INFO) transforming nested_type attributes for upjet v1 compatibility
	@python3 hack/transform-schema.py $(TERRAFORM_PROVIDER_SCHEMA)
	@$(OK) schema transformation complete

.PHONY: $(TERRAFORM_PROVIDER_SCHEMA) pull-provider
# ====================================================================================
# Targets

# NOTE: the build submodule currently overrides XDG_CACHE_HOME in order to
# force the Helm 3 to use the .work/helm directory. This causes Go on Linux
# machines to use that directory as the build cache as well. We should adjust
# this behavior in the build submodule because it is also causing Linux users
# to duplicate their build cache, but for now we just make it easier to identify
# its location in CI so that we cache between builds.
go.cachedir:
	@go env GOCACHE

# Generate a coverage report for cobertura applying exclusions on
# - generated file
cobertura:
	@cat $(GO_TEST_OUTPUT)/coverage.txt | \
		grep -v zz_ | \
		$(GOCOVER_COBERTURA) > $(GO_TEST_OUTPUT)/cobertura-coverage.xml

# Update the submodules, such as the common build scripts.
submodules:
	@git submodule sync
	@git submodule update --init --recursive

# This is for running out-of-cluster locally, and is for convenience. Running
# this make target will print out the command which was used. For more control,
# try running the binary directly with different arguments.
run: go.build
	@$(INFO) Running Crossplane locally out-of-cluster . . .
	@# To see other arguments that can be provided, run the command with --help instead
	UPBOUND_CONTEXT="local" $(GO_OUT_DIR)/provider --debug

# ====================================================================================
# End to End Testing
CROSSPLANE_NAMESPACE = upbound-system
-include build/makelib/local.xpkg.mk
-include build/makelib/controlplane.mk

uptest: $(UPTEST) $(KUBECTL) $(KUTTL)
	@$(INFO) running automated tests
	@KUBECTL=$(KUBECTL) KUTTL=$(KUTTL) $(UPTEST) e2e "${UPTEST_EXAMPLE_LIST}" --setup-script=cluster/test/setup.sh || $(FAIL)
	@$(OK) running automated tests

local-deploy: build controlplane.up local.xpkg.deploy.provider.$(PROJECT_NAME)
	@$(INFO) running locally built provider
	@$(KUBECTL) wait provider.pkg $(PROJECT_NAME) --for condition=Healthy --timeout 5m
	@$(KUBECTL) -n upbound-system wait --for=condition=Available deployment --all --timeout=5m
	@$(OK) running locally built provider

e2e: local-deploy uptest

.PHONY: cobertura submodules fallthrough run crds.clean

# ====================================================================================
# Special Targets

define CROSSPLANE_MAKE_HELP
Crossplane Targets:
    cobertura             Generate a coverage report for cobertura applying exclusions on generated files.
    submodules            Update the submodules, such as the common build scripts.
    run                   Run crossplane locally, out-of-cluster. Useful for development.

endef
# The reason CROSSPLANE_MAKE_HELP is used instead of CROSSPLANE_HELP is because the crossplane
# binary will try to use CROSSPLANE_HELP if it is set, and this is for something different.
export CROSSPLANE_MAKE_HELP

crossplane.help:
	@echo "$$CROSSPLANE_MAKE_HELP"

help-special: crossplane.help

.PHONY: crossplane.help help-special
