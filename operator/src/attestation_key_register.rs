// SPDX-FileCopyrightText: Alice Frosi <afrosi@redhat.com>
//
// SPDX-License-Identifier: MIT

use anyhow::Result;
use futures_util::StreamExt;
use k8s_openapi::{
    ByteString,
    api::{
        apps::v1::{Deployment, DeploymentSpec},
        core::v1::{
            Container, ContainerPort, PodSpec, PodTemplateSpec, Secret, Service, ServicePort,
            ServiceSpec,
        },
    },
    apimachinery::pkg::{
        apis::meta::v1::{LabelSelector, ObjectMeta, OwnerReference},
        util::intstr::IntOrString,
    },
};
use kube::{
    Api, Client, Resource,
    api::{ListParams, ObjectList, Patch, PatchParams},
    runtime::{Controller, controller::Action, watcher},
};
use log::info;
use serde_json::json;
use std::{collections::BTreeMap, sync::Arc};
use trusted_cluster_operator_lib::{
    AttestationKey, AttestationKeyStatus, Machine, conditions::ATTESTATION_KEY_MACHINE_APPROVE,
    update_status,
};

use crate::conditions::attestation_key_approved_condition;
use crate::trustee;
use operator::{ControllerError, controller_error_policy, create_or_info_if_exists};

const INTERNAL_ATTESTATION_KEY_REGISTER_PORT: i32 = 8001;

pub async fn create_attestation_key_register_deployment(
    client: Client,
    owner_reference: OwnerReference,
    image: &str,
) -> Result<()> {
    let name = "attestation-key-register";
    let app_label = "attestation-key-register";
    let labels = BTreeMap::from([("app".to_string(), app_label.to_string())]);

    let deployment = Deployment {
        metadata: ObjectMeta {
            name: Some(name.to_string()),
            owner_references: Some(vec![owner_reference]),
            ..Default::default()
        },
        spec: Some(DeploymentSpec {
            replicas: Some(1),
            selector: LabelSelector {
                match_labels: Some(labels.clone()),
                ..Default::default()
            },
            template: PodTemplateSpec {
                metadata: Some(ObjectMeta {
                    labels: Some(labels.clone()),
                    ..Default::default()
                }),
                spec: Some(PodSpec {
                    service_account_name: Some("trusted-cluster-operator".to_string()),
                    containers: vec![Container {
                        name: name.to_string(),
                        image: Some(image.to_string()),
                        ports: Some(vec![ContainerPort {
                            container_port: INTERNAL_ATTESTATION_KEY_REGISTER_PORT,
                            ..Default::default()
                        }]),
                        args: Some(vec![
                            "--port".to_string(),
                            INTERNAL_ATTESTATION_KEY_REGISTER_PORT.to_string(),
                        ]),
                        ..Default::default()
                    }],
                    ..Default::default()
                }),
            },
            ..Default::default()
        }),
        ..Default::default()
    };

    create_or_info_if_exists!(client, Deployment, deployment);
    info!("Attestation key register deployment created successfully");
    Ok(())
}

pub async fn create_attestation_key_register_service(
    client: Client,
    owner_reference: OwnerReference,
    attestation_key_register_port: Option<i32>,
) -> Result<()> {
    let name = "attestation-key-register";
    let app_label = "attestation-key-register";
    let labels = BTreeMap::from([("app".to_string(), app_label.to_string())]);

    let service = Service {
        metadata: ObjectMeta {
            name: Some(name.to_string()),
            labels: Some(labels.clone()),
            owner_references: Some(vec![owner_reference]),
            ..Default::default()
        },
        spec: Some(ServiceSpec {
            selector: Some(labels),
            ports: Some(vec![ServicePort {
                name: Some("http".to_string()),
                port: attestation_key_register_port
                    .unwrap_or(INTERNAL_ATTESTATION_KEY_REGISTER_PORT),
                target_port: Some(IntOrString::Int(INTERNAL_ATTESTATION_KEY_REGISTER_PORT)),
                protocol: Some("TCP".to_string()),
                ..Default::default()
            }]),
            type_: Some("ClusterIP".to_string()),
            ..Default::default()
        }),
        ..Default::default()
    };

    create_or_info_if_exists!(client, Service, service);
    info!("Attestation key register service created successfully");
    Ok(())
}

async fn ak_reconcile(
    ak: Arc<AttestationKey>,
    client: Arc<Client>,
) -> Result<Action, ControllerError> {
    info!(
        "Attestation Key reconciliation for: {}",
        ak.metadata.name.clone().unwrap_or_default()
    );
    let client = Arc::unwrap_or_clone(client);
    let machines: Api<Machine> = Api::default_namespaced(client.clone());
    let lp = ListParams::default();
    let machine_list: ObjectList<Machine> = machines.list(&lp).await.map_err(|e| {
        eprintln!("Error fetching machine list: {}", e);
        ControllerError::Anyhow(e.into())
    })?;
    for machine in &machine_list.items {
        if ak.spec.address.as_ref() == Some(&machine.spec.registration_address) {
            approve_ak(&ak, machine, client.clone()).await?;
            return Ok(Action::await_change());
        }
    }
    Ok(Action::await_change())
}

async fn machine_reconcile(
    machine: Arc<Machine>,
    client: Arc<Client>,
) -> Result<Action, ControllerError> {
    info!(
        "Machine reconciliation for: {}",
        machine.metadata.name.clone().unwrap_or_default()
    );
    let client = Arc::unwrap_or_clone(client);
    let machine_address = machine.spec.registration_address.clone();

    if machine_address == "" {
        info!("Machine IP not set, skipping reconciliation");
        return Ok(Action::await_change());
    }

    let aks: Api<AttestationKey> = Api::default_namespaced(client.clone());
    let lp = ListParams::default();
    let ak_list: ObjectList<AttestationKey> = aks.list(&lp).await.map_err(|e| {
        eprintln!("Error fetching attestation key list: {}", e);
        ControllerError::Anyhow(e.into())
    })?;
    for ak in ak_list.items {
        if let Some(ak_address) = &ak.spec.address {
            if *ak_address == machine_address {
                approve_ak(&ak, &machine, client.clone()).await?;
                return Ok(Action::await_change());
            }
        }
    }
    Ok(Action::await_change())
}

async fn approve_ak(ak: &AttestationKey, machine: &Machine, client: Client) -> Result<()> {
    let name = ak.metadata.name.clone().unwrap_or_else(|| String::new());
    let aks: Api<AttestationKey> = Api::default_namespaced(client.clone());

    let is_approved = ak
        .status
        .as_ref()
        .and_then(|s| s.conditions.as_ref())
        .map(|conditions| {
            conditions
                .iter()
                .any(|c| c.type_ == "Approved" && c.status == "True")
        })
        .unwrap_or(false);

    if !is_approved {
        let generation = ak.metadata.generation;
        let condition =
            attestation_key_approved_condition(ATTESTATION_KEY_MACHINE_APPROVE, generation);
        let mut conditions = ak
            .status
            .as_ref()
            .and_then(|s| s.conditions.clone())
            .unwrap_or_default();
        conditions.push(condition);

        let status = AttestationKeyStatus {
            conditions: Some(conditions),
        };
        update_status!(aks, &name, status)?;
        info!("Approved attestation key {name}");
    }

    let machine_name = machine.metadata.name.clone().unwrap_or_default();
    let has_machine_owner = ak
        .metadata
        .owner_references
        .as_ref()
        .map(|owners| {
            owners
                .iter()
                .any(|owner| owner.kind == "Machine" && owner.name == machine_name)
        })
        .unwrap_or(false);

    if !has_machine_owner {
        let machine_owner_reference = OwnerReference {
            api_version: Machine::api_version(&()).to_string(),
            kind: Machine::kind(&()).to_string(),
            name: machine_name,
            uid: machine.metadata.uid.clone().unwrap_or_default(),
            controller: Some(true),
            block_owner_deletion: Some(true),
        };

        let patch = json!({
            "metadata": {
                "ownerReferences": [machine_owner_reference]
            }
        });

        aks.patch(&name, &PatchParams::default(), &Patch::Merge(&patch))
            .await?;
        info!("Set Machine as owner of AttestationKey {name}");
    }

    let secret_name = format!("ak-{}", name);
    let secrets: Api<Secret> = Api::default_namespaced(client.clone());
    let secret_exists = secrets.get(&secret_name).await.is_ok();

    if !secret_exists {
        let public_key_data = ByteString(ak.spec.public_key.as_bytes().to_vec());
        let data = BTreeMap::from([("public_key".to_string(), public_key_data)]);

        let owner_reference = OwnerReference {
            api_version: AttestationKey::api_version(&()).to_string(),
            kind: AttestationKey::kind(&()).to_string(),
            name: name.clone(),
            uid: ak.metadata.uid.clone().unwrap_or_default(),
            controller: Some(true),
            block_owner_deletion: Some(true),
        };

        let secret = Secret {
            metadata: ObjectMeta {
                name: Some(secret_name.clone()),
                owner_references: Some(vec![owner_reference]),
                ..Default::default()
            },
            data: Some(data),
            ..Default::default()
        };

        create_or_info_if_exists!(client.clone(), Secret, secret);
        info!("Created secret {secret_name} for attestation key {name}");

        trustee::mount_attestation_key(client.clone(), &secret_name).await?;
    }

    Ok(())
}

pub async fn launch_ak_controller(client: Client) {
    let aks: Api<AttestationKey> = Api::default_namespaced(client.clone());
    tokio::spawn(
        Controller::new(aks, watcher::Config::default())
            .run(ak_reconcile, controller_error_policy, Arc::new(client))
            .for_each(|res| async move {
                match res {
                    Ok(o) => info!("reconciled {o:?}"),
                    Err(e) => info!("reconcile failed: {e:?}"),
                }
            }),
    );
}

pub async fn launch_machine_ak_controller(client: Client) {
    let machines: Api<Machine> = Api::default_namespaced(client.clone());
    tokio::spawn(
        Controller::new(machines, watcher::Config::default())
            .run(machine_reconcile, controller_error_policy, Arc::new(client))
            .for_each(|res| async move {
                match res {
                    Ok(o) => info!("machine reconciled for ak approval {o:?}"),
                    Err(e) => info!("machine reconcile failed: {e:?}"),
                }
            }),
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mock_client::*;

    #[tokio::test]
    async fn test_create_ak_register_depl_success() {
        let clos = |client| {
            create_attestation_key_register_deployment(client, Default::default(), "image")
        };
        test_create_success::<_, _, Deployment>(clos).await;
    }

    #[tokio::test]
    async fn test_create_ak_register_depl_error() {
        let clos = |client| {
            create_attestation_key_register_deployment(client, Default::default(), "image")
        };
        test_create_error(clos).await;
    }

    #[tokio::test]
    async fn test_create_ak_register_svc_success() {
        let clos =
            |client| create_attestation_key_register_service(client, Default::default(), None);
        test_create_success::<_, _, Service>(clos).await;
    }

    #[tokio::test]
    async fn test_create_ak_register_svc_error() {
        let clos =
            |client| create_attestation_key_register_service(client, Default::default(), Some(80));
        test_create_error(clos).await;
    }
}
