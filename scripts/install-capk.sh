#!/bin/bash

set -e

source scripts/common.sh
CAPI_VERSION=1.10.4

${KIND} export kubeconfig

install_metallb() {
	METALLB_VER=$(curl "https://api.github.com/repos/metallb/metallb/releases/latest" | jq -r ".tag_name")
	kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VER}/config/manifests/metallb-native.yaml"
	kubectl wait pods -n metallb-system -l app=metallb,component=controller --for=condition=Ready --timeout=10m
	kubectl wait pods -n metallb-system -l app=metallb,component=speaker --for=condition=Ready --timeout=2m

	if [ "$RUNTIME" == "podman" ]; then
		SUBNET=$($RUNTIME network inspect kind | jq -r '.[0].subnets[] | select(.subnet | test("^[0-9.]+/")) | .subnet')
		PREFIX=$(echo $SUBNET | sed -E 's|^([0-9]+\.[0-9]+)\..*$|\1|g')
	else
		SUBNET=$(docker network inspect -f '{{range .IPAM.Config}}{{if .Gateway}}{{.Subnet}}{{end}}{{end}}' kind)
		PREFIX=$(echo $SUBNET | sed -E 's|^([0-9]+\.[0-9]+)\..*$|\1|g')
	fi
	cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: capi-ip-pool
  namespace: metallb-system
spec:
  addresses:
  - ${PREFIX}.255.200-${PREFIX}.255.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: empty
  namespace: metallb-system
EOF
}

install_kubevirt() {
	KV_VER=$(curl "https://api.github.com/repos/kubevirt/kubevirt/releases/latest" | jq -r ".tag_name")
	kubectl apply -f "https://github.com/kubevirt/kubevirt/releases/download/${KV_VER}/kubevirt-operator.yaml"
	kubectl apply -f "https://github.com/kubevirt/kubevirt/releases/download/${KV_VER}/kubevirt-cr.yaml"
	kubectl wait -n kubevirt kv kubevirt --for=condition=Available --timeout=10m
}

export CLUSTER_TOPOLOGY=true

install_clusterctl
install_metallb
install_kubevirt

${CLUSTERCTL} init --infrastructure kubevirt
