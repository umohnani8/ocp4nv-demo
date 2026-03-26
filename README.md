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
  osImageURL: quay.io/openshift-release-dev/ocp-v4.0-art-dev:4.21-10.1-ocp4nv-preview-202603161953-node-image
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
6.12.0-209.2.el10nv.aarch64+64k
```

This confirms the deployment succeeded.

---

## Step 5: Building the DTK image

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

Add the custom tag to the driver-toolkit imagestream
```
oc tag quay.io/ravanelli/staging:dtk-4nv-03172026 openshift/driver-toolkit:custom-dtk -n openshift
```

Verify the tag was added
```
oc get is/driver-toolkit -n openshift -o yaml
```

## Step 7: Install and uninstall the NFD operator

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

Now let's remove the NFD instance and operator. **The labels will persist.**
```
oc delete nodefeaturediscovery nfd-instance -n openshift-nfd
oc delete subscription nfd -n openshift-nfd
oc delete -n openshift-nfd $(oc get csv -n openshift-nfd -o name | grep nfd)
```

## Step 8: Label node with custom DTK tag

Label the GPU nodes with the custom DTK tag.

List the GPU nodes.
```
oc get nodes
```

Add label to specify custom DTK tag (replace <GPU_NODE_NAME> with actual node name).
```
oc label node <GPU_NODE_NAME> \
    nvidia.com/gpu.driver-toolkit-imagestream-tag=custom-dtk \
    --overwrite
```

Verify the label was added.
```
oc get node <GPU_NODE_NAME> --show-labels | grep driver-toolkit
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

First update the [clusterPolicy YAML](https://github.com/umohnani8/ocp4nv-demo/blob/main/gpu-cluster-policy.yaml) with your custom image. 

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
6.12.0-209.2.el10nv.aarch64+64k
```
