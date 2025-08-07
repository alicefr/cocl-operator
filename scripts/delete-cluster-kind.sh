#!/bin/bash

source scripts/common.sh
$KIND delete cluster
$RUNTIME rm -f kind-registry
