ORG?=grafana-operator
NAMESPACE?=grafana
PROJECT=grafana-operator
REG?=quay.io
SHELL=/bin/bash
TAG?=v3.10.3
PKG=github.com/grafana-operator/grafana-operator
COMPILE_TARGET=./build/_output/bin/$(PROJECT)

GOOS ?= $(shell go env GOOS)
GOARCH ?= $(shell go env GOARCH)

# list for multi-arch image publishing
TARGET_ARCHS ?= amd64 arm64

.PHONY: setup/travis
setup/travis:
	@echo Installing Operator SDK
	@curl -Lo operator-sdk https://github.com/operator-framework/operator-sdk/releases/download/v0.12.0/operator-sdk-v0.12.0-x86_64-linux-gnu && chmod +x operator-sdk && sudo mv operator-sdk /usr/local/bin/

.PHONY: code/run
code/run:
	@operator-sdk run local --namespace=${NAMESPACE}

.PHONY: code/compile
code/compile:
	GOOS=$(GOOS) GOARCH=$(GOARCH) CGO_ENABLED=0 go build -o=$(COMPILE_TARGET)-$(GOARCH) ./cmd/manager

.PHONY: code/compile/amd64
code/compile/amd64:
	GOOS=linux GOARCH=amd64 $(MAKE) code/compile

.PHONY: code/compile/arm64
code/compile/arm64:
	GOOS=linux GOARCH=arm64 $(MAKE) code/compile

.PHONY: code/gen
code/gen:
	operator-sdk generate k8s

.PHONY: code/check
code/check:
	@diff -u <(echo -n) <(gofmt -d .)

.PHONY: code/fix
code/fix:
	@gofmt -w .

.PHONY: image/build
image/build: code/compile
	@operator-sdk build ${REG}/${ORG}/${PROJECT}:${TAG}

.PHONY: image/push
image/push:
	docker push ${REG}/${ORG}/${PROJECT}:${TAG}

.PHONY: image/build/push
image/build/push: image/build image/push

.PHONY: test/unit
test/unit:
	@echo Running tests:
	go test -v -race -cover ./pkg/...

.PHONY: test/e2e
test/e2e:
	@operator-sdk --verbose test local ./test/e2e --watch-namespace="grafana-test-e2e" --operator-namespace="grafana-test-e2e" --debug --up-local

.PHONY: cluster/prepare/local/file
cluster/prepare/local/file:
	@sed -i "s/__NAMESPACE__/${NAMESPACE}/g" deploy/cluster_roles/cluster_role_binding_grafana_operator.yaml

.PHONY: cluster/prepare/local
cluster/prepare/local: cluster/prepare/local/file
	-kubectl create namespace ${NAMESPACE}
	kubectl apply -f deploy/crds
	kubectl apply -f deploy/roles -n ${NAMESPACE}
	kubectl apply -f deploy/cluster_roles
	kubectl apply -f deploy/examples/Grafana.yaml -n ${NAMESPACE}

.PHONY: cluster/cleanup
cluster/cleanup: operator/stop
	-kubectl delete deployment grafana-deployment -n ${NAMESPACE}
	-kubectl delete namespace ${NAMESPACE}

## Deploy the latest tagged release
.PHONY: operator/deploy
operator/deploy: cluster/prepare/local
	kubectl apply -f deploy/operator.yaml -n ${NAMESPACE}
	@git checkout -- deploy/cluster_roles/cluster_role_binding_grafana_operator.yaml

## Deploy the latest master image
.PHONY: operator/deploy/master
operator/deploy/master: cluster/prepare/local
	kubectl apply -f deploy/operatorMasterImage.yaml -n ${NAMESPACE}
	@git checkout -- deploy/cluster_roles/cluster_role_binding_grafana_operator.yaml

.PHONY: operator/stop
operator/stop:
	-kubectl delete deployment grafana-operator -n ${NAMESPACE}
