
# Coder Kubevirt Template
[![Apache 2.0 License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](https://choosealicense.com/licenses/apache-2.0/)

This project is a template to create reproducible dev environments in [Coder](https://github.com/coder/coder) using [Kubevirt](https://github.com/kubevirt/kubevirt) running on a Kubernetes cluster.

Coder enables organizations to set up development environments in their public or private cloud infrastructure. Cloud development environments are defined with Terraform, connected through a secure high-speed Wireguard® tunnel, and are automatically shut down when not in use to save on costs. Coder gives engineering teams the flexibility to use the cloud for workloads that are most beneficial to them.

KubeVirt is a virtual machine management add-on for Kubernetes. The aim is to provide a common ground for virtualization solutions on top of Kubernetes.

Read below for motive.

## Pre-requisites
- A running kubernetes cluster with Kubevirt deployed. See Kubevirt [installation guide](https://kubevirt.io/user-guide/operations/installation).
- Containerized Data Importer (CDI) should be installed in the kubernetes cluster for PVC management. See CDI [installation guide](https://kubevirt.io/user-guide/operations/containerized_data_importer/).
- Default storage class configured in the kubernetes cluster.
- Bare-metal kubernetes cluster preferred. For kubernetes clusters running on top of VMs, nested-virtualization support is required.

#### Kubernetes API Access Pre-requisite
If the Coder host is running outside the Kubernetes cluster (where workspace VMs will be deployed), a valid "~/.kube/config" must be present on the Coder host.

If Coder host is deployed on the same Kubernetes cluster (where workspace VMs will be deployed), a service account provisioned by coder will be used for workspace deployments. 

In both cases, the service-account/user(in the kubeconfig) should have bindings for following roles:

| type        	| apiGroups            	| resources                 	| verbs            	| namespace                                      	|
|-------------	|----------------------	|---------------------------	|------------------	|------------------------------------------------	|
| clusterrole 	| apiextensions.k8s.io 	| customresourcedefinitions 	| get, list, watch 	| -                                              	|
| clusterrole 	| kubevirt.io          	| virtualmachines           	| *                	| -                                              	|
| clusterrole 	| cdi.kubevirt.io      	| datavolumes               	| *                	| -                                              	|
| role        	| ""                   	| secrets                   	| *                	| namespace where workspace VMs will be deployed 	|
| role        	| ""                   	| services                   	| *                	| namespace where workspace VMs will be deployed 	|

Permission to access secret in the namespace where VMs are deployed is required to store cloud-init configs. This secret is then mount to workspace VMs as a cloud-init drive. Kubevirt only supports 2048 byte cloud-init config if set as string. To overcome this limit, Kubernetes secrets are used.

Permission to access service in the namespace where VMs are deployed is required to add DNS entry of VMs in the Kubernetes cluster. This way a VM created by this template can be accessed by another VM in the same cluster very easily. This can be done without DNS entry, and service as well, by referring to the "pod" IP address of the VM directly. This template runs VM network in `masquerade` mode. This means that the network VM will be is different than the k8s pod network. Network traffic is NAT'ed from VM network to pod network in `masquerade` mode. The VMs won't be accessible from other VMs by using the internal VM IP address. One has to use the "pod" IP address to access the VM. Since getting the pod IP address can only be done by someone who has access to the cluster, DNS entry is added to the k8s cluster instead. This way, anyone who uses coder and does not have access to the underlying k8s cluster will be able to access other VMs.

VMs created by this template can be accessed in the following format:
`coder-<owner>-<workspace-name>.<namespace>.svc.cluster.local`

## Features

- Provision KVM Virtual Machines as dev workspaces
- Persists whole root filesystem instead of just home directory
- Persists software installs in the OS
- Code server is enabled by default
- SSH is configured
- VMs can be started/stopped/restarted from Coder webapp without losing data
- Major Linux distributions are pre-configured
    - Ubuntu 22.04
    - Debian 12
    - Fedora 39
    - Arch Linux
    - AlmaLinux 9
    - CentOS Stream 9
    - Rocky Linux 9
- Automatically downloads OS drives from cloud to create disk PVCs

## Installation 
This installation assumes you have a Coder deployment running and CLI authenticated.

- Clone this repository
```sh
git clone https://github.com/sulo1337/coder-kubevirt-template.git && cd coder-kubevirt-template/kubevirt-provisioner
```
- Push the template
```sh
coder templates push .
```

## Defaults
These are the default values configured in the template. These values can be changed based on the requirements

- CPU - 2 cores
- Memory - 4Gi
- Disk Size - 16Gi
- Network configured in masquerade mode. See [kubevirt networking documentation](https://kubevirt.io/user-guide/virtual_machines/interfaces_and_networks/) for more details

## Roadmap
- Enable sourcing disk PVC creations from another PVC. Currently disk PVC data is sourced from qcow2 cloud images of various OS. This feature will allow a cluster administrator to pre-configure bootable image of an OS as PVC and use that PVC as a source to create new VM disk.
- Windows OS as VMs
- VNC 
- Multi-disk VMs 
- Shared disks as PVC attached to VMs allowing dev workspaces to share files.

## Notes
- Management of Kubevirt is out of scope of this repository
- VolumeSnapshot and PVC backups of VM disks is out of scope of this repository


## Motive
I created this template because of three reasons. 
- To safely allow container runtimes to run inside coder workspace
- To utilize existing Kubernetes cluster to provision workspaces capable of running native container workloads
- To use existing bare-metal infrastructure for provisioning coder workspaces instead of using cloud providers (AWS, Azure etc)

There are other benefits to using Virtual Machine vs Containers for dev environments which is out of scope for this documentation.


Workspaces provisioned by Coder in Kubernetes are container environments in a pod. Most modern software development requires use of containerization technologies like Docker as a part of development workflow. According to [Coder Docs](https://coder.com/docs/v2/latest/templates/docker-in-workspaces), there are multiple ways to run container environments inside pods provisioned by Coder:
- Sysbox container runtime (needs specific infrastructure configuration, and enterprise license for [more features](https://github.com/nestybox/sysbox/blob/master/docs/figures/sysbox-features.png))
- Envbox*
- Rootless podman*
- Privileged docker sidecar*

*All of these methods either will make you create a privileged pod inside your cluster or have some privileged wrapper around your workspace (except rootless podman). Limitations of using rootless podman is out of scope for this documentation.

I created this template to extend Coder's functionality to provision VMs on existing Kubernetes clusters. KVM machines being used as coder workspaces unlocks these functionalities:
- docker inside coder workspaces
- systemd
- mini kubernetes environments inside coder workspaces using [minikube](https://github.com/kubernetes/minikube) or [kind](https://github.com/kubernetes-sigs/kind)
- access to raw devices (needs configuration)
- nested virtualization inside coder workspace (needs configuration)
- more isolation from host compared to pods
and many more...
