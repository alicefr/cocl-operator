#!/bin/bash

CONT_RUNTIME=${CONT_RUNTIME:=podman}
ROOT=${ROOT:=false}
export KIND=kind
if [ "$CONT_RUNTIME" == "podman" ]; then
	export KIND_EXPERIMENTAL_PROVIDER=podman
	if [ ${ROOT} ]; then
		export DOCKER_HOST=unix://run/podman/podman.sock
		export RUNTIME="sudo -E podman"
		export KIND="sudo -E kind"
	else
		export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock
		RUNTIME=podman
	fi
else
	RUNTIME=docker
fi

BIN_DIR=.out
CLUSTERCTL=${BIN_DIR}/clusterctl

install_clusterctl() {
	mkdir -p ${BIN_DIR}
	if [ ! -f ${CLUSTERCTL}]; then
		curl -L \
			https://github.com/kubernetes-sigs/cluster-api/releases/download/v${CAPI_VERSION}/clusterctl-linux-amd64 \
			-o ${CLUSTERCTL}

		chmod +x ${CLUSTERCTL}
	fi
}

