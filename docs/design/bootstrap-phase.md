# Bootstrap Phase Design

## Overview

This document describes the bootstrap phase for Trusted Execution Clusters, specifically addressing the challenge of bringing up the first control plane nodes in a confidential computing environment.

The bootstrap phase presents a unique challenge: to attest and provision the initial control plane nodes, we need a functioning attestation infrastructure (Trustee and operator), but these components would traditionally run within the cluster being bootstrapped. This creates a circular dependency that must be resolved through an external trust anchor.

## Problem Statement

In a standard Trusted Execution Cluster deployment, the operator and Trustee server run within the cluster itself. However, during the bootstrap phase:

1. **No Control Plane Yet**: The cluster being provisioned has no running control plane to host the operator or Trustee
2. **Attestation Required**: The first control plane nodes still require attestation to ensure they meet security requirements before being trusted
3. **Key Management**: LUKS encryption keys for the bootstrap nodes must be registered and accessible during initial provisioning
4. **Policy Enforcement**: Attestation and resource policies must be in place before the first nodes attempt attestation

## External Trustee and Operator

The bootstrap phase requires an **external trusted Kubernetes cluster** that serves as the trust anchor for provisioning the new confidential cluster. This external cluster hosts the operator and Trustee infrastructure during the bootstrap phase.

### Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│  External Trusted Kubernetes Cluster                         │ 
│  (Pre-existing, Trust Anchor)                                │
│                                                              │
│  ┌──────────────────────────┐  ┌─────────────────────────┐   │
│  │ Trusted Execution        │  │ Trustee                 │   │
│  │ Cluster Operator         │  │                         │   │
│  │                          │  └─────────────────────────┘   |                      │  │ - Deployment of trustee  │  ┌─────────────────────────┐   │
│  │   and registration server│  │ Registration server     │   │
│  │ - Secret Management      │  │                         │   │
│  | - Policies managment     |  └─────────────────────────┘   |
|  |                          |                                |
|  └──────────────────────────┘                                |
│                                                              │
│  Publicly Accessible Endpoints:                              │
│  - Registration Service: http(s)://<external>/register       │
│  - Attestation/KBS: http(s)://<external>/kbs                 │
└──────────────────────────────┬───────────────────────────────┘
                               │
                               │ Network connectivity required
                               │ during bootstrap
                               │
┌──────────────────────────────┴───────────────────────────────┐
│  New Confidential Cluster                                    │
│  (Being Bootstrapped)                                        │
│                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │
│  │  Control    │  │ Control-    │  │ Control     │           │
│  │   plane 1   │  │  plane 2    │  │ plane 3     │           │
│  │             │  │             │  │             │           │
│  │ - Contacts  │  │ - Contacts  │  │ - Contacts  │           │
│  │   external  │  │   external  │  │   external  │           │
│  │   endpoints │  │   endpoints │  │   endpoints │           │
│  └─────────────┘  └─────────────┘  └─────────────┘           │
└──────────────────────────────────────────────────────────────┘
```

## Bootstrap phase

Before beginning the bootstrap phase, the cluster administrator must:

1. **Establish External Trusted Cluster**: Deploy or identify an existing Kubernetes cluster that will serve as the trust anchor
   - This cluster must be considered trusted and secure
   - Must be accessible from the network where new cluster nodes will be provisioned

2. **Deploy Operator on External Cluster**: Install the Trusted Execution Cluster Operator on the external cluster
   - Configure it to manage resources for the new cluster being bootstrapped

3. **Configure Network Accessibility**: Ensure the following endpoints are reachable from the new cluster's network
   - **Registration Service**: Must be accessible by nodes during firstboot for Ignition merge
   - **Attestation Key Registration**: Required for TPM-based attestation key registration
   - **KBS Endpoints**: Required for attestation and key retrieval during both firstboot and subsequent boots

4. **Approve Bootstrap Images**: Create ApprovedImage resources for the bootable images that will be used for bootstrap nodes
   - Ensure reference values are computed and registered with Trustee
   - Verify attestation policies are in place
   

## Migration of the operator in cluster
TBD


