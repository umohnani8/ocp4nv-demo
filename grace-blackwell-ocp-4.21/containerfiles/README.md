## Build and Push the Custom Layered Image

Using a tool like **Podman** or **Buildah**, build your custom OS and DTK images from the provided containerfiles.

Because this is an **out-of-cluster build**, you must:

- Authenticate with your registry using your **pull secret**
- Run the build on a **RHEL/Fedora system registered with subscription-manager**
- Build the **DTK image on an aarch64 host** (native ARM64 environment)

When using Podman on a subscribed RHEL/Fedora host, Red Hat entitlements are automatically made available inside the build environment, allowing access to RHEL/UBI repositories during `dnf install`.

For more details, see:
https://access.redhat.com/solutions/253273

After building, push the resulting image to your **private Quay repository**.