#!/bin/sh
set -xo errexit

source scripts/common.sh

if [ "$($KIND get clusters 2>/dev/null)" != "kind" ]; then
	$KIND create cluster --config kind/config.yaml --wait 5m
fi

reg_name='kind-registry'
reg_port='5000'
if [ "$($RUNTIME inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)" != 'true' ]; then
  $RUNTIME run --network kind \
    -d --restart=always -p "127.0.0.1:${reg_port}:5000" --name "${reg_name}" \
    registry:2
fi

REGISTRY_DIR="/etc/containerd/certs.d/localhost:${reg_port}"
for node in $($KIND get nodes); do
  $RUNTIME exec "${node}" mkdir -p "${REGISTRY_DIR}"
  cat <<EOF | $RUNTIME exec -i "${node}" cp /dev/stdin "${REGISTRY_DIR}/hosts.toml"
[host."http://${reg_name}:5000"]
EOF
done

if [ "$($RUNTIME inspect -f='{{json .NetworkSettings.Networks.kind}}' "${reg_name}")" = 'null' ]; then
  $RUNTIME network connect "kind" "${reg_name}"
fi

rm .kubeconfig
scripts/kubeconfig.sh
export KUBECONFIG=$(pwd)/.kubeconfig

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${reg_port}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF
