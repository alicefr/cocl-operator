#!/bin/bash

# TODO: switch to podman root
export CONT_RUNTIME=docker

source scripts/common.sh

$KIND create cluster --config kind/config-kubevirt-cluster.yaml
kubectl create -f  https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/calico.yaml

