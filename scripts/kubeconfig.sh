#!/bin/bash

source scripts/common.sh

config=$(pwd)/.kubeconfig
$KIND get kubeconfig > $config
echo "set export KUBECONFIG=$config"
