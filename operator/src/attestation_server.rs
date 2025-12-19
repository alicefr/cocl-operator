// SPDX-FileCopyrightText: Alice Frosi <afrosi@redhat.com>
//
// SPDX-License-Identifier: MIT

use anyhow::Result;
use k8s_openapi::{
    api::{
        apps::v1::{Deployment, DeploymentSpec},
        core::v1::{
            Container, ContainerPort, PodSpec, PodTemplateSpec, Service, ServicePort, ServiceSpec,
        },
    },
    apimachinery::pkg::{
        apis::meta::v1::{LabelSelector, ObjectMeta, OwnerReference},
        util::intstr::IntOrString,
    },
};
use kube::Client;
use log::info;
use std::collections::BTreeMap;

use operator::create_or_update;

const INTERNAL_ATTESTATION_SERVER_PORT: i32 = 8001;

pub async fn create_attestation_server_deployment(
    client: Client,
    owner_reference: OwnerReference,
    image: &str,
) -> Result<()> {
    let name = "attestation-server";
    let app_label = "attestation-server";
    let labels = BTreeMap::from([("app".to_string(), app_label.to_string())]);

    let mut deployment = Deployment {
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
                    service_account_name: Some("cocl-operator".to_string()),
                    containers: vec![Container {
                        name: name.to_string(),
                        image: Some(image.to_string()),
                        ports: Some(vec![ContainerPort {
                            container_port: INTERNAL_ATTESTATION_SERVER_PORT,
                            ..Default::default()
                        }]),
                        args: Some(vec![
                            "--port".to_string(),
                            INTERNAL_ATTESTATION_SERVER_PORT.to_string(),
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

    create_or_update!(client, Deployment, deployment);
    info!("Attestation server deployment created/updated successfully");
    Ok(())
}

pub async fn create_attestation_server_service(
    client: Client,
    owner_reference: OwnerReference,
    attestation_server_port: Option<i32>,
) -> Result<()> {
    let name = "attestation-server";
    let app_label = "attestation-server";
    let labels = BTreeMap::from([("app".to_string(), app_label.to_string())]);

    let mut service = Service {
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
                port: attestation_server_port.unwrap_or(INTERNAL_ATTESTATION_SERVER_PORT),
                target_port: Some(IntOrString::Int(INTERNAL_ATTESTATION_SERVER_PORT)),
                protocol: Some("TCP".to_string()),
                ..Default::default()
            }]),
            type_: Some("ClusterIP".to_string()),
            ..Default::default()
        }),
        ..Default::default()
    };

    create_or_update!(client, Service, service);
    info!("Attestation server service created/updated successfully");
    Ok(())
}
