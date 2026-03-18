# This builds the OCP4NV node image on top of the base image itself.
FROM quay.io/openshift-release-dev/ocp-v4.0-art-dev:4.21-10.1-node-image

ARG KERNEL_URL="https://kojihub.stream.centos.org/kojifiles/vol/koji02/packages/kernel/6.12.0"
ARG KERNEL_VERSION="211.4.el10nv"

RUN set -eux; \
    arch="$(uname -m)"; \
    if { [ "$arch" = "x86_64" ] || [ "$arch" = "aarch64" ]; }; then \
        baseurl="${KERNEL_URL}/${KERNEL_VERSION}/${arch}"; \
        mkdir -p /tmp/new-kernel && cd /tmp/new-kernel; \
        curl -s "${baseurl}/" \
          | grep -oE 'kernel(-64k)?(-(core|modules|modules-core|modules-extra))?-[0-9][^"]+\.rpm' \
          | grep -vE '(modules-internal|modules-partner|devel|headers|debug)' \
          | sort -u \
          | xargs -r -I{} curl -s -O "${baseurl}/{}"; \
        rpm-ostree override remove kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra; \
        rpm-ostree install /tmp/new-kernel/*.rpm; \
        rm -rf /tmp/new-kernel; \
    fi

RUN ostree container commit
