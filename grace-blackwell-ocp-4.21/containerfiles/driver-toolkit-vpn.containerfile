# This is adapted from https://github.com/Okoyl/rhcos-nv/blob/master/driver-toolkit.containerfile

FROM registry.access.redhat.com/ubi10:latest AS builder

ARG KERNEL_VERSION="211.4.el10nv"
ARG KERNEL_URL="https://kojihub.stream.centos.org/kojifiles/vol/koji02/packages/kernel/6.12.0"


RUN cat <<EOF > /etc/yum.repos.d/rhcos.repo

[rhel-9-appstream]
name=rhel-9-appstream
baseurl=https://rhsm-pulp.corp.redhat.com/content/dist/rhel9/9.0/aarch64/appstream/os/
enabled=1
# Temporarily disable RPM signature
# See: https://github.com/coreos/rhel-coreos-config/issues/146
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[rhel-10.1-baseos]
name=rhel-10.1-baseos
baseurl=https://rhsm-pulp.corp.redhat.com/content/dist/rhel10/10.1/aarch64/baseos/os/
enabled=1
# Temporarily disable RPM signature
# See: https://github.com/coreos/rhel-coreos-config/issues/146
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[rhel-10.1-appstream]
name=rhel-10.1-appstream
baseurl=https://rhsm-pulp.corp.redhat.com/content/dist/rhel10/10.1/aarch64/appstream/os/
enabled=1
# Temporarily disable RPM signature
# See: https://github.com/coreos/rhel-coreos-config/issues/146
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[rhel-10.1-nfv]
name=rhel-10.1-nfv
baseurl=https://rhsm-pulp.corp.redhat.com/content/dist/rhel10/10.1/aarch64/nfv/os/
enabled=1
# Temporarily disable RPM signature
# See: https://github.com/coreos/rhel-coreos-config/issues/146
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[rhel-10.1-highavailability]
name=rhel-10.1-highavailability
baseurl=https://rhsm-pulp.corp.redhat.com/content/dist/rhel10/10.1/aarch64/highavailability/os/
enabled=1
# Temporarily disable RPM signature
# See: https://github.com/coreos/rhel-coreos-config/issues/146
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[rhel-10.1-fast-datapath]
name=rhel-10.1-fast-datapath
# NOTE this one is still using GA content
baseurl=https://rhsm-pulp.corp.redhat.com/content/dist/layered/rhel10/aarch64/fast-datapath/os/
enabled=1
# Temporarily disable RPM signature
# See: https://github.com/coreos/rhel-coreos-config/issues/146
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
EOF

RUN set -eux; \
    arch="$(uname -m)"; \
    if [ "$arch" = "x86_64" ] || [ "$arch" = "aarch64" ]; then \
        baseurl="${KERNEL_URL}/${KERNEL_VERSION}/${arch}"; \
        mkdir -p /tmp/new-kernel && cd /tmp/new-kernel; \
        curl -k "${baseurl}/" \
          | grep -oE 'kernel(-64k)?(-(core|modules|modules-core|modules-extra|rpm-macros|srpm-macros|headers|devel|devel-matched))?-[0-9][^"]+\.rpm' \
          | grep -vE '(modules-internal|modules-partner|debug|uki-virt)' \
          | sort -u \
          | xargs -r -I{} curl -f -k -O "${baseurl}/{}"; \
        ls -l /tmp; \
        echo "Installing new kernel packages..."; \
        rpm -ivh --nodeps --noscripts /tmp/new-kernel/kernel-*.rpm; \
    fi

    # Additional packages that are mandatory for driver-containers
RUN dnf -y install elfutils-libelf-devel kmod binutils kabi-dw glibc

# Find and install the GCC version used to compile the kernel
# If it cannot be found (fails on some architectures), install the default gcc
RUN export INSTALLED_KERNEL=$(rpm -q --qf "%{VERSION}-%{RELEASE}.%{ARCH}"  kernel-devel) && \
  GCC_VERSION=$(cat /lib/modules/${INSTALLED_KERNEL}/config | grep -Eo "gcc \(GCC\) ([0-9\.]+)" | grep -Eo "([0-9\.]+)") && \
  dnf -y install gcc-${GCC_VERSION} gcc-c++-${GCC_VERSION} || dnf -y install gcc gcc-c++

  # Additional packages that are needed for a subset (e.g DPDK) of driver-containers
RUN dnf -y install xz diffutils flex bison

# Packages needed to build driver-containers
RUN dnf -y install git make rpm-build

# Packages needed to sign and run externally build kernel modules
RUN if [ $(arch) == "x86_64" ] || [ $(arch) == "aarch64" ]; then \
  ARCH_DEP_PKGS="mokutil"; fi \
  && dnf -y install openssl keyutils $ARCH_DEP_PKGS

  RUN dnf clean all
ARG TAGS=''
RUN if echo "${TAGS:-}" | grep -q scos > /dev/null 2>&1; then sed -i 's/rhel-coreos/stream-coreos/g' /manifests/*; fi
LABEL io.k8s.description="driver-toolkit is a container with the kernel packages necessary for building driver containers for deploying kernel modules/drivers on OpenShift" \
  name="driver-toolkit" \
  io.openshift.release.operator=true \
  version="0.1"

# Last layer for metadata for mapping the driver-toolkit to a specific kernel version
RUN export INSTALLED_KERNEL=$(rpm -q --qf "%{VERSION}-%{RELEASE}.%{ARCH}"  kernel-devel); \
  export INSTALLED_RT_KERNEL=$(rpm -q --qf "%{VERSION}-%{RELEASE}.%{ARCH}+rt"  kernel-rt-core); \
  echo "{ \"KERNEL_VERSION\": \"${INSTALLED_KERNEL}\", \"RT_KERNEL_VERSION\": \"${INSTALLED_RT_KERNEL}\", \"RHEL_VERSION\": \"$(</etc/dnf/vars/releasever)\" }" > /etc/driver-toolkit-release.json
