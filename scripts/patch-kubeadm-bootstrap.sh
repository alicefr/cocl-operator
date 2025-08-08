#!/bin/bash
set -xe

# Patch the CAPI kubeadm bootstrap controller to enable KubeadmBootstrapFormatIgnition feature gate

echo "Getting all arguments from deployment..."

# Get all arguments as JSON array
ARGS_JSON=$(kubectl get deploy capi-kubeadm-bootstrap-controller-manager -n capi-kubeadm-bootstrap-system -o jsonpath='{.spec.template.spec.containers[0].args}')

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
        kubectl patch deploy capi-kubeadm-bootstrap-controller-manager \
          -n capi-kubeadm-bootstrap-system \
          --type='json' \
          -p="[{\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/args/$i\", \"value\": \"$NEW_ARG\"}]"
        
        echo "Deployment patched successfully. Waiting for rollout to complete..."
        kubectl rollout status deployment/capi-kubeadm-bootstrap-controller-manager -n capi-kubeadm-bootstrap-system
        
        echo "Feature gate KubeadmBootstrapFormatIgnition is now enabled."
        exit 0
    fi
done

echo "Error: feature-gates argument not found!"
exit 1
