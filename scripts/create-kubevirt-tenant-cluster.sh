#!/bin/bash

set -e

source scripts/common.sh
export NODE_VM_IMAGE_TEMPLATE="quay.io/capk/ubuntu-2404-container-disk:v1.32.1"
export CAPK_GUEST_K8S_VERSION="${NODE_VM_IMAGE_TEMPLATE/*:/}"
export CRI_PATH="unix:///var/run/containerd/containerd.sock"

${CLUSTERCTL} generate cluster capi-quickstart \
  --infrastructure="kubevirt" \
  --flavor lb \
  --kubernetes-version ${CAPK_GUEST_K8S_VERSION} \
  --control-plane-machine-count=1 \
  --worker-machine-count=1 \
  > cluster.yaml

kubectl apply -f cluster.yaml
