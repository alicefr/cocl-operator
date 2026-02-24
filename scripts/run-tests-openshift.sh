#!/bin/bash

usage() {
    echo "Usage: $0 -i <image> [-u <user>]"
    echo "  -i    Image file (VHD) to upload"
    echo "  -u    User name (optional, defaults to oc whoami)"
    exit 1
}

while getopts "i:u:" opt; do
    case $opt in
        i)
            TEST_IMAGE="$OPTARG"
            ;;
        u)
            USER="$OPTARG"
            ;;
        *)
            usage
            ;;
    esac
done

if [ -z "$TEST_IMAGE" ]; then
    echo "Error: Image is required"
    usage
fi

# Set user to oc whoami if not provided
if [ -z "$USER" ]; then
    USER=$(oc whoami)
fi

CLI_RUNTIME=${CLI_RUNTIME:-podman}
export VIRT_PROVIDER=azure
export PLATFORM=openshift

NAMESPACE=$USER-test
oc create ns $NAMESPACE
oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
HOST=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')
podman login $HOST -u $USER -p $(oc whoami -t) --tls-verify=false
export REGISTRY=$HOST/$NAMESPACE
make push
oc policy add-role-to-group system:image-puller system:serviceaccounts --namespace=$NAMESPACE
# Export REGISTRY to the internal URL
export REGISTRY=image-registry.openshift-image-registry.svc:5000/$NAMESPACE
make integration-tests
