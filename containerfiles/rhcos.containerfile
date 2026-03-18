# This builds the OCP4NV node image on top of the base image itself.
FROM quay.io/openshift-release-dev/ocp-v4.0-art-dev:4.21-10.1-node-image
ARG KERNEL_VERSION="209.2.el10nv"
RUN set -eux; \
    arch="$(uname -m)"; \
    if { [ "$arch" = "x86_64" ] || [ "$arch" = "aarch64" ]; }; then \
        baseurl="https://download-01.beak-001.prod.iad2.dc.redhat.com/brewroot/vol/rhel-10/packages/kernel/6.12.0/${KERNEL_VERSION}/${arch}"; \
        cd /tmp; \
        curl -s "${baseurl}/" \
          | grep -oE 'kernel(-64k)?(-(core|modules|modules-core|modules-extra))?-[0-9][^"]+\.rpm' \
          | grep -vE '(modules-internal|modules-partner|devel|headers|debug)' \
          | sort -u \
          | xargs -r -I{} curl -s -O "${baseurl}/{}"; \
        echo "Detecting installed kernel packages..."; \
        pkgs="$(rpm -qa | grep -E '^kernel(-64k)?(-(core|modules|modules-core|modules-extra))?$' || true)"; \
        # The packages names are different from what is installed
        if [ -n "$pkgs" ]; then \
            echo "Removing: $pkgs"; \
            rpm-ostree override remove $pkgs; \
        else \
            echo "No kernel packages to remove"; \
        fi; \
        echo "Installing new kernel packages..."; \
        rpm-ostree install /tmp/kernel*.rpm; \
        rm -f /tmp/kernel*.rpm; \
    fi
RUN ostree container commit
