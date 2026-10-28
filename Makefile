SHELL := /bin/bash
ROOT := $(CURDIR)
BIN := $(ROOT)/.bin
CHART := charts/spark-connect

OS := $(shell uname -s | tr A-Z a-z)
UNAME_M := $(shell uname -m)
ARCH := $(if $(filter aarch64 arm64,$(UNAME_M)),arm64,amd64)
DOCS_ARCH := $(if $(filter arm64,$(ARCH)),arm64,x86_64)
DOCS_OS := $(shell uname -s)

# renovate: datasource=github-releases depName=helm/helm
HELM_VERSION ?= v4.3.1
# renovate: datasource=github-releases depName=helm-unittest/helm-unittest
HELM_UNITTEST_VERSION ?= v1.2.1
# renovate: datasource=github-releases depName=kubernetes-sigs/kind
KIND_VERSION ?= v0.33.0
# renovate: datasource=github-releases depName=kubernetes/kubernetes
KUBECTL_VERSION ?= v1.37.2
# renovate: datasource=github-releases depName=norwoodj/helm-docs
HELM_DOCS_VERSION ?= v1.14.2
# renovate: datasource=github-releases depName=yannh/kubeconform
KUBECONFORM_VERSION ?= v0.8.0
# renovate: datasource=github-releases depName=losisin/helm-values-schema-json
HELM_SCHEMA_VERSION ?= v2.6.0

export HELM_PLUGINS := $(BIN)/plugins
export PATH := $(BIN):$(PATH)
HELM := $(BIN)/helm

.PHONY: tools lint unittest
tools: $(BIN)/.tools-$(HELM_VERSION)-$(HELM_UNITTEST_VERSION)-$(KIND_VERSION)-$(KUBECTL_VERSION)-$(HELM_DOCS_VERSION)-$(KUBECONFORM_VERSION)-$(HELM_SCHEMA_VERSION)

$(BIN)/.tools-%:
	rm -rf $(BIN)
	mkdir -p $(BIN)/plugins/unittest $(BIN)/plugins/schema
	curl -fsSL https://get.helm.sh/helm-$(HELM_VERSION)-$(OS)-$(ARCH).tar.gz | tar xz -C $(BIN) --strip-components=1 $(OS)-$(ARCH)/helm
	curl -fsSL https://github.com/helm-unittest/helm-unittest/releases/download/$(HELM_UNITTEST_VERSION)/helm-unittest-$(OS)-$(ARCH)-$(HELM_UNITTEST_VERSION:v%=%).tgz | tar xz -C $(BIN)/plugins/unittest
	curl -fsSL https://github.com/losisin/helm-values-schema-json/releases/download/$(HELM_SCHEMA_VERSION)/helm-values-schema-json_$(HELM_SCHEMA_VERSION:v%=%)_$(OS)_$(ARCH).tgz | tar xz -C $(BIN)/plugins/schema
	curl -fsSL -o $(BIN)/kind https://github.com/kubernetes-sigs/kind/releases/download/$(KIND_VERSION)/kind-$(OS)-$(ARCH)
	curl -fsSL -o $(BIN)/kubectl https://dl.k8s.io/release/$(KUBECTL_VERSION)/bin/$(OS)/$(ARCH)/kubectl
	curl -fsSL https://github.com/norwoodj/helm-docs/releases/download/$(HELM_DOCS_VERSION)/helm-docs_$(HELM_DOCS_VERSION:v%=%)_$(DOCS_OS)_$(DOCS_ARCH).tar.gz | tar xz -C $(BIN) helm-docs
	curl -fsSL https://github.com/yannh/kubeconform/releases/download/$(KUBECONFORM_VERSION)/kubeconform-$(OS)-$(ARCH).tar.gz | tar xz -C $(BIN) kubeconform
	chmod +x $(BIN)/kind $(BIN)/kubectl
	touch $@

lint: tools
	$(HELM) lint $(CHART)

unittest: tools
	$(HELM) unittest $(CHART)
