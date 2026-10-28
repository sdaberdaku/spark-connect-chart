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
# renovate: datasource=github-releases depName=mikefarah/yq
YQ_VERSION ?= v4.54.1
# renovate: datasource=github-releases depName=yannh/kubeconform
KUBECONFORM_VERSION ?= v0.8.0
# renovate: datasource=github-releases depName=losisin/helm-values-schema-json
HELM_SCHEMA_VERSION ?= v2.6.0

export HELM_PLUGINS := $(BIN)/plugins
export PATH := $(BIN):$(PATH)
HELM := $(BIN)/helm

# Kubernetes minors validated by kubeconform: the last three in its default schema repo
# (yannh/kubernetes-json-schema; check it has the new minor before bumping).
K8S_VERSIONS := 1.35.0 1.36.0 1.37.0
CRD_SCHEMAS := https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json
# renovate: datasource=docker depName=quay.io/helmpack/chart-testing
CT_IMAGE ?= quay.io/helmpack/chart-testing:v3.15.0
CT_ARGS ?=

.PHONY: e2e tools schema docs lint unittest kubeconform ct-lint package versions-check check
tools: $(BIN)/.tools-$(HELM_VERSION)-$(HELM_UNITTEST_VERSION)-$(KIND_VERSION)-$(KUBECTL_VERSION)-$(HELM_DOCS_VERSION)-$(KUBECONFORM_VERSION)-$(HELM_SCHEMA_VERSION)-$(YQ_VERSION)

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
	curl -fsSL -o $(BIN)/yq https://github.com/mikefarah/yq/releases/download/$(YQ_VERSION)/yq_$(OS)_$(ARCH)
	chmod +x $(BIN)/yq $(BIN)/kind $(BIN)/kubectl
	touch $@

schema: tools
	cd $(CHART) && $(HELM) schema -f values.yaml --draft 7 --schema-root.additional-properties=false -o values.schema.json

docs: tools
	helm-docs --chart-search-root charts
	mkdir -p docs/site
	cp $(CHART)/README.md docs/site/values.md

lint: tools schema docs
	$(HELM) lint $(CHART)

unittest: tools schema docs
	$(HELM) unittest $(CHART)

# Validates the rendered manifests and the executor pod template (a Pod inside a ConfigMap) for the default and all-on values.
kubeconform: tools schema docs
	@set -e; for v in $(CHART)/ci/default-values.yaml $(CHART)/ci/all-on-values.yaml; do \
	  $(HELM) template x $(CHART) -f $$v > $(BIN)/rendered.yaml; \
	  yq 'select(.kind == "ConfigMap" and .data["executor-pod-template.yaml"]) | .data["executor-pod-template.yaml"]' $(BIN)/rendered.yaml > $(BIN)/executor.yaml; \
	  test -s $(BIN)/executor.yaml || { echo "executor pod template not found in rendered output"; exit 1; }; \
	  for k in $(K8S_VERSIONS); do \
	    echo "== $$v on Kubernetes $$k"; \
	    kubeconform -strict -summary -kubernetes-version $$k -schema-location default -schema-location '$(CRD_SCHEMAS)' $(BIN)/rendered.yaml $(BIN)/executor.yaml; \
	  done; \
	done

ct-lint: tools schema docs
	docker run --rm -v $(ROOT):/work -w /work $(CT_IMAGE) sh -c 'git config --global --add safe.directory /work && ct lint --config ct.yaml $(CT_ARGS)'

package: tools schema docs
	$(HELM) package $(CHART) -d dist/

versions-check:
	@python3 -c "import json,re;t=lambda v:tuple(map(int,v.split('.')));a=re.search(r'^appVersion: \"?([\d.]+)',open('$(CHART)/Chart.yaml').read(),re.M).group(1);m=max((e['spark'] for e in json.load(open('spark-versions.json'))),key=t);assert a==m,f'appVersion {a} != highest spark {m}';print('appVersion',a,'ok')"

check: lint unittest kubeconform versions-check

SPARK_VERSION ?= $(shell sed -n 's/^appVersion: "\?\([0-9.]*\).*/\1/p' $(CHART)/Chart.yaml)
e2e: tools schema
	SPARK_VERSION=$(SPARK_VERSION) e2e/run.sh
