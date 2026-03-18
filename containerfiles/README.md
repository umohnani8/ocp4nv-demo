## Build and Push the Custom Layered Image

Using a tool like **Podman** or **Buildah**, build your custom OS and DTK images from the provided containerfiles.

Because this is an **out-of-cluster build**, make sure to authenticate with your registry using your **pull secret**.

Push the resulting image to your **private Quay repository**.

These containerfiles are adapted from [https://github.com/Okoyl/rhcos-nv](https://github.com/Okoyl/rhcos-nv) to not require entitlements.