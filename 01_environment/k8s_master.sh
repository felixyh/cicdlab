# Disable SELinux
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=disabled/' /etc/selinux/config

# Disable firewall permanently
systemctl disable firewalld --now
systemctl mask --now firewalld


# Diable swap temporally
swapoff -a

#永久禁掉swap分区，注释掉swap那一行
sed -ri 's/.*swap.*/#&/' /etc/fstab

# Adjust kernel parameters
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system

# Load netfilter kernel module
modprobe br_netfilter
lsmod | grep br_netfilter

# Network gateway and proxy settings, only GW=192.168.0.250 can reach TW proxy=10.64.1.81:8080
route -n | grep -i ug

# Set proxy for os system
export HTTPS_PROXY="10.64.1.81:8080"
export HTTP_PROXY="10.64.1.81:8080"
export NO_PROXY="10.64.0.0/16,172.168.1.0/24,127.0.0.0/8,10.0.0.0/8,192.168.0.0/16"

# Set proxy for docker
mkdir /etc/systemd/system/docker.service.d
cat << EOF > /etc/systemd/system/docker.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=10.64.1.81:8080"
Environment="HTTPS_PROXY=10.64.1.81:8080"
Environment="NO_PROXY=localhost,127.0.0.0/8,10.0.0.0/8,192.168.0.0/16,docker-registry.somecorporation.com"
EOF

# Reload and restart docker
systemctl daemon-reload && systemctl restart docker

# Show docker proxy settings
systemctl show --property Environment docker

# Install required packages. yum-utils provides the yum-config-manager utility, and device-mapper-persistent-data and lvm2 are required by the devicemapper storage driver.
yum install -y yum-utils device-mapper-persistent-data lvm2

# Use the following command to set up the stable repository
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Remove podman buildah to avoid the error: "Error: Problem 1: problem with installed package podman-1:3.4.1-3.module_el8.6.0+954+963caf36.x86_64 - package podman-1:3.4.1-3.module_el8.6.0+954+963caf36.x86_64 requires runc >= 1.0.0-57, but none of the providers can be installed"
yum erase -y podman buildah

# Install docker
yum install -y docker-ce docker-ce-cli containerd.io


systemctl start docker &&  systemctl enable docker

# Install kubeadm, kubelet and kubectl with Aliyun repo
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF

# Set SELinux in permissive mode (effectively disabling it)
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config


sudo yum -y install kubeadm-1.18.20 kubelet-1.18.20 kubectl-1.18.20


cat <<EOF > /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf
# Note: This dropin only works with kubeadm and kubelet v1.11+
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
Environment="KUBELET_CGROUP_ARGS=--cgroup-driver=cgroupfs"
# This is a file that "kubeadm init" and "kubeadm join" generates at runtime, populating the KUBELET_KUBEADM_ARGS variable dynamically
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
# This is a file that the user can use for overrides of the kubelet args as a last resort. Preferably, the user should use
# the .NodeRegistration.KubeletExtraArgs object in the configuration files instead. KUBELET_EXTRA_ARGS should be sourced from this file.
EnvironmentFile=-/etc/sysconfig/kubelet
ExecStart=
ExecStart=/usr/bin/kubelet \$KUBELET_KUBECONFIG_ARGS \$KUBELET_CONFIG_ARGS \$KUBELET_KUBEADM_ARGS \$KUBELET_EXTRA_ARGS \$KUBELET_CGROUP_ARGS
EOF



systemctl daemon-reload && systemctl restart kubelet
sudo systemctl enable --now kubelet

# restart container CRI
rm -rf /etc/containerd/config.toml
systemctl restart containerd

kubeadm init --pod-network-cidr=10.100.0.0/16


mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"

sudo curl --proxy 10.64.1.81:8080 -L git.io/weave -o /usr/local/bin/weave
sudo chmod a+x /usr/local/bin/weave
weave ps
weave status
weave status peers
weave status connections

