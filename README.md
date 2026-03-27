# Deploying a Custom RHCOS4NV in OpenShift

## Prerequisites

Before starting, ensure the following requirements are met:

- The OpenShift cluster must be running **OpenShift 4.21.z**.

## Step 1: Create the MachineConfig Object

Create a YAML file to instruct the cluster to boot with the custom RHCOS4NV image.

**The official custom RHCOS4NV images are available at:**

- `quay.io/openshift-release-dev/ocp-v4.0-art-dev:4.21-10.1-ocp4nv-preview-202603161953-node-image` (209.2.el10nv)
- `quay.io/openshift-release-dev/ocp-v4.0-art-dev:4.21-10.1-ocp4nv-preview-202603182257-node-image` (211.4.el10nv)

This is a manifest list and has support for both **aarch64** and **amd64**.


```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker # Target the pool with the NVIDIA nodes (using worker for the example here)
  name: 99-worker-custom-os
spec:
  # The osImageURL is the key field here
  osImageURL: quay.io/openshift-release-dev/ocp-v4.0-art-dev:4.21-10.1-ocp4nv-preview-202603182257-node-image
```

## Step 2: Apply the MachineConfig

Apply the custom object to your cluster:

```bash
oc create -f machineconfig.yaml
```

Once applied, the **Machine Config Operator** takes over. It will automatically:

- Render a new machine config
- Perform **cordon and drain** operations on worker nodes
- Apply the custom layered image
- Reboot the nodes to use the new OS image

---

## Step 3: Monitor the Rollout

You can monitor the rollout by checking the **MachineConfigPool** status:

```bash
oc get mcp -w
```

- When **UPDATING = True**, the pool is actively updating.
- When **UPDATING = False** and **UPDATED = True**, the rollout is complete.

---

## Step 4: Verify the Node and Kernel Version

Once the nodes return to a **Ready** state, verify that they booted into the correct kernel.

```bash
oc get nodes
oc get mcp
oc get nodes -o custom-columns=NAME:.metadata.name,KERNEL:.status.nodeInfo.kernelVersion
```

Confirm that the node reports the following kernel:

```
6.12.0-211.4.el10nv.aarch64+64k
```

This confirms the deployment succeeded.

---

## Step 5: Building the Driver ToolKit image

A custom DTK image using the same kernel is needed to install the GPU operator.

Build your own DTK image using this [containerfile](https://github.com/umohnani8/ocp4nv-demo/blob/main/containerfiles/driver-toolkit.containerfile).

Note: Since this is an out-of-cluster build, you must:

Authenticate to your registry using your pull secret
Run the build on a RHEL or Fedora system registered with subscription-manager
Build the DTK image on an aarch64 host (native ARM64 environment)

If you are building in an environment with VPN access and prefer not to register the system for entitlements, you must configure the internal repositories instead. In that case, use this [containerfile](https://github.com/umohnani8/ocp4nv-demo/blob/main/containerfiles/driver-toolkit-vpn.containerfile).

Use the following command to the build the image
```
# Build your own driver toolkit image
podman build -f driver-toolkit.containerfile --tag "driver-toolkit-cs:4.21.z"
```

**There are existing images that can be used for testing purposes:**

- `quay.io/ravanelli/staging:dtk-4nv-03172026` (209.2.el10nv)
- `quay.io/ravanelli/staging:dtk-4nv-03182026-211.4el0nv` (211.4.el10nv)

## Step 6: Add custom DTK tag to the DTK imagestream

Add the custom tag to the driver-toolkit imagestream. The NVIDIA operators that we will install in future steps looks for a DTK image with a `10.1.x` tag.
```
oc tag quay.io/ravanelli/staging:dtk-4nv-03182026-211.4el0nv openshift/driver-toolkit:10.1.20260126-0 -n openshift
```

Verify the tag was added
```
oc get is/driver-toolkit -n openshift -o yaml
```

## Step 7: Install the NFD operator

**Detailed instructions on installing the NFD and GPU operators can be found [here](https://docs.nvidia.com/datacenter/cloud-native/openshift/latest/introduction.html).**

Install the NFD operator to get the appropriate labels on the nodes that we will override in a later step.

```
oc apply -f nfd-operator-install.yaml
```

Wait for the pod to be ready.
```
oc get pods -n openshift-nfd -w
```

Create the NFD instance so that the nodes are labelled.
```
oc apply -f nfd-instance.yaml
```

Wait a few seconds for the labels to be added to the nodes. It can be verified with the following command.
```
oc get nodes --show-labels | grep feature.node
```

## Step 8: Install the NVIDIA Network Operator

Note that as of this writing the v26.1 release of the NVIDIA Network Operator was not available for OpenShift 4.21 so v25.10 of the operator is being used here.

Install the Network Operator.
```
oc apply -f network-operator-install.yaml
```

Wait for the pods to be ready.
```
oc get pods -n nvidia-network-operator -w
```

Now that the operator is up and running we can go ahead and configure a basic driver policy. In order to match the kernel we have installed on this cluster, we have to do some tagging magic from NVIDIA's registry and then push it up to our own private registry. Need to tag from `rhel10.0` to `rhel10.1`.
```
podman tag nvcr.io/nvidia/mellanox/doca-driver:doca3.3.0-26.01-1.0.0.0-0-rhel10.0-arm64 quay.io/redhat_emp1/ecosys-nvidia/doca-driver:doca3.3.0-26.01-1.0.0.0-0-rhel10.1-arm64
podman push quay.io/redhat_emp1/ecosys-nvidia/doca-driver:doca3.3.0-26.01-1.0.0.0-0-rhel10.1-arm64
```

Now in the NicClusterPolicy we can specific the DOCA version and it will be able to find the right tag from our registry.

Create the NicClusterPolicy.
```
oc create -f nic-cluster-policy.yaml
```

Wait for the pods to be ready. The NicClusterPolicy will take ~5 minutes to complete as it builds the drivers and then ultimately unloads the in-tree mlx5 drivers and loads the out-of-tree drivers. After that time we should see mofed pods that are in a 2/2 ready state. The number of mofed pods will be based on the number of nodes that have valid Mellanox devices in them.
```
oc get pods -n nvidia-network-operator -w
```

Further validation can be done by execing into the mofed pod and running a few commands.
```
oc rsh -n nvidia-network-operator [mofed-pod-name]
sh-5.2# lsmod|grep mlx5
sh-5.2# ofed_info
```

## Step 9: Install the GPU operator

For this to work, GPU nodes are needed.

```
oc apply -f gpu-operator-install.yaml
```

Wait for the GPU operator to be ready
```
oc get pods -n nvidia-gpu-operator -w
```

## Step 10: Deploy ClusterPolicy that uses a custom image

First update the [clusterPolicy YAML](https://github.com/umohnani8/ocp4nv-demo/blob/main/gpu-cluster-policy.yaml) with your custom driver image. 

Create the clusterPolicy.
```
oc apply -f gpu-cluster-policy.yaml
```

Monitor the GPU operator pods deployment
```
oc get pods -n nvidia-gpu-operator -w
```

## Step 11: Run GPU Burn Workload

```
oc apply -f gpu-burn-workload.yaml
```

Monitor the gpu-burn pod
```
oc logs -f gpu-burn
```

Check GPU status inside the pod
```
oc exec -it gpu-burn -- nvidia-smi
```

---

## For Day 0 Support

Extract the *openshift-install* binary from a 4.21.z release payload.
```
oc adm release extract -a <PULL_SECRET_PATH> --command=openshift-install <OCP_4.21.Z_RELEASE_PAYLOAD>
```

Create the manifests.
```
./openshift-install create manifests
```

Add the custom osImageURL MachineConfig YAML from **Step 1** above under the *openshift* directory created by the manifests step.
```
touch openshift/99-worker-osImgURL.yaml
```

Create the cluster.
```
./openshift-install create cluster
```

Once the cluster is up and the nodes are in **Ready** state, verify that they booted into the correct kernel.

```bash
oc get nodes
oc get mcp
oc get nodes -o custom-columns=NAME:.metadata.name,KERNEL:.status.nodeInfo.kernelVersion
```

Confirm that the node reports the following kernel:

```
6.12.0-211.4.el10nv.aarch64+64k
```
