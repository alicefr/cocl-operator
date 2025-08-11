#!/bin/bash
set -xe

# Patch CAPI kubeadm controllers to enable KubeadmBootstrapFormatIgnition feature gate

patch_deployment() {
    local DEPLOYMENT_NAME=$1
    local NAMESPACE=$2
    
    echo "Patching $DEPLOYMENT_NAME in namespace $NAMESPACE..."
    echo "Getting all arguments from deployment..."

    # Get all arguments as JSON array
    ARGS_JSON=$(kubectl get deploy $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].args}')

    echo "Current arguments: $ARGS_JSON"

    # Convert JSON array to bash array
    readarray -t ARGS < <(echo "$ARGS_JSON" | jq -r '.[]')

    # Find and update the feature-gates argument
    for i in "${!ARGS[@]}"; do
        if [[ "${ARGS[$i]}" == *"--feature-gates="* ]]; then
            echo "Found feature-gates argument at index $i: ${ARGS[$i]}"
            
            # Replace KubeadmBootstrapFormatIgnition=false with true
            NEW_ARG=$(echo "${ARGS[$i]}" | sed 's/KubeadmBootstrapFormatIgnition=false/KubeadmBootstrapFormatIgnition=true/')
            
            echo "Updated argument: $NEW_ARG"
            
            # Patch the specific argument
            kubectl patch deploy $DEPLOYMENT_NAME \
              -n $NAMESPACE \
              --type='json' \
              -p="[{\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/args/$i\", \"value\": \"$NEW_ARG\"}]"
            
            echo "Deployment patched successfully. Waiting for rollout to complete..."
            kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NAMESPACE
            
            echo "Feature gate KubeadmBootstrapFormatIgnition is now enabled for $DEPLOYMENT_NAME."
            return 0
        fi
    done

    echo "Error: feature-gates argument not found in $DEPLOYMENT_NAME!"
    return 1
}

# Patch both deployments
patch_deployment "capi-kubeadm-bootstrap-controller-manager" "capi-kubeadm-bootstrap-system"
patch_deployment "capi-kubeadm-control-plane-controller-manager" "capi-kubeadm-control-plane-system"

echo "All deployments patched successfully!"
