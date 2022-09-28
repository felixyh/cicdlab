[TOC]

# Preparation

## Lab servers

OS image: CentOS 8 stream

K8S Master: 192.168.22.61
K8S Node-1: 192.168.22.62
K8S Node-2: 192.168.22.63

## Initial environment setup for master and node servers

Environment_ini.sh

```bash
# Disable SELinux
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=disabled/' /etc/selinux/config

# Disable firewall permanently
systemctl disable firewalld --now
systemctl mask --now firewalld
#systemctl status firewalld

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
```



## Set proxy for Lab environment

Proxy_set.sh

```bash
# Set proxy for os system
export HTTPS_PROXY="10.64.1.81:8080"
export HTTP_PROXY="10.64.1.81:8080"
export NO_PROXY="10.64.0.0/16,172.168.1.0/24,127.0.0.0/8,10.0.0.0/8,192.168.0.0/16"
```



## Install Docker for master and node servers

Docker_install.sh

```bash
# Install required packages. yum-utils provides the yum-config-manager utility, and device-mapper-persistent-data and lvm2 are required by the devicemapper storage driver.
yum install -y yum-utils device-mapper-persistent-data lvm2

# Use the following command to set up the stable repository
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Remove podman buildah to avoid the error: "Error: Problem 1: problem with installed package podman-1:3.4.1-3.module_el8.6.0+954+963caf36.x86_64 - package podman-1:3.4.1-3.module_el8.6.0+954+963caf36.x86_64 requires runc >= 1.0.0-57, but none of the providers can be installed"
yum erase -y podman buildah

# Install docker
yum install -y docker-ce docker-ce-cli containerd.io

# If need to install a specific version, can use below commands
## yum list docker-ce --showduplicates | sort -r
## sudo yum install docker-ce-<VERSION_STRING> docker-ce-cli-<VERSION_STRING> containerd.io
## for example: 3:19.03.2-3.el7
## yum install docker-ce-<3:19.03.2-3.el7> docker-ce-cli-<3:19.03.2-3.el7> containerd.io
# Start and Enable Docker
systemctl start docker &&  systemctl enable docker


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
```



# Install Kubernetes

## [Installing kubeadm, kubelet and kubectl](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#installing-kubeadm-kubelet-and-kubectl) on Master and node servers

K8s_install.sh

```bash
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


# sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
# install version 1.23.5 which is stable version. Installing lastest version usually have unknown issue when initialization
sudo yum -y install kubeadm-1.23.5 kubelet-1.23.5 kubectl-1.23.5


# !!! before enable kubelet, need to ensure docker and kubelet driver are the same, otherwise, there's below error message after "kubeadm init" command: "cgroup and systemd are not matched"
# [error: failed to run Kubelet: failed to create kubelet: misconfiguration: kubelet cgroup driver: “systemd” is different from docker cgroup driver: “cgroupfs”]

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

###################
# !!! before enable kubelet, need to ensure docker and kubelet driver are the same, otherwise, there's below error message after "kubeadm init" command: "cgroup and systemd are not matched"
# [error: failed to run Kubelet: failed to create kubelet: misconfiguration: kubelet cgroup driver: “systemd” is different from docker cgroup driver: “cgroupfs”]

# vi  /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf


#Update below parameter:
#Environment="KUBELET_CGROUP_ARGS=--cgroup-driver=cgroupfs"
#ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS $KUBELET_CGROUP_ARGS
#######################

systemctl daemon-reload && systemctl restart kubelet
sudo systemctl enable --now kubelet
```







## Init Kubenetes with network and configure kubectl as regular user on Master server

Network_kubectl_user.sh

```bash
# restart container CRI
rm -rf /etc/containerd/config.toml
systemctl restart containerd

kubeadm init --pod-network-cidr=10.100.0.0/16
#参考：如果要指定Kubernetes的版本,可以用一下命令
#kubeadm init --kubernetes-version=v1.15.1 --pod-network-cidr=10.100.0.0/16

# 如果初始化失败，记得执行清空
# kubeadm reset

# 卸载管理组件
# yum erase -y kubelet kubectl kubeadm kubernetes-cni


mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```



## Install network plugin and weave tool on Master server

Network_plugin.sh

```bash
# Install network plugin weave
kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"

sudo curl --proxy 10.64.1.81:8080 -L git.io/weave -o /usr/local/bin/weave
sudo chmod a+x /usr/local/bin/weave
weave ps
weave status
weave status peers
weave status connections
```





# Post-Installation

## Join node server to master

Node_join.sh

```bash
# avoid error: [ERROR FileContent–proc-sys-net-ipv4-ip_forward]: /proc/sys/net/ipv4/ip_forward contents are not set to 1
echo 1 > /proc/sys/net/ipv4/ip_forward

# Below command is copied from the output of the "kubeadm init"
kubeadm join 192.168.22.81:6443 --token d0cbz5.9nugb974yhl54ss6 \
	--discovery-token-ca-cert-hash sha256:bc7099ce8ff86c2cc7d8d51b0f30c4d57cbd3fbe967e81f8f05c2decf9599b07 

# Check K8S cluster nodes and pods status
kubectl get nodes
kubectl get pods --all-namespaces -o wide
```





## Install helm3 on K8SMaster

Helm3_install.sh

```bash
wget -e "https_proxy=10.64.1.81:8080"  https://get.helm.sh/helm-v3.1.2-linux-amd64.tar.gz
tar -zxvf helm-v3.1.2-linux-amd64.tar.gz
cd linux-amd64/
mv helm /usr/bin/
helm version


# helm init is not used any more since helm3
# $ kubectl create serviceaccount --namespace kube-system tiller
# $ kubectl create clusterrolebinding tiller-cluster-role --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
# $ helm init --upgrade -i registry.cn-hangzhou.aliyuncs.com/google_containers/tiller:v2.15.1 --service-account=tiller --stable-repo-url https://kubernetes.oss-cn-hangzhou.aliyuncs.com/charts![title](/api/file/getImage?fileId=620bb3b4935fe2000e000015)
# add helm repo
helm repo add  aliyuncs https://apphub.aliyuncs.com
helm repo list
helm search repo aliyuncs | head -5
```

### something more about helm

```bash
# add helm repo
[root@CentOS001 ~]# helm repo add stable http://mirror.azure.cn/kubernetes/charts
"stable" has been added to your repositories
[root@CentOS001 ~]# helm repo add aliyun  https://kubernetes.oss-cn-hangzhou.aliyuncs.com/charts
"aliyun" has been added to your repositories
[root@CentOS001 ~]# helm repo add jetstack https://charts.jetstack.io
"jetstack" has been added to your repositories

# update helm repo
[root@CentOS001 ~]# helm repo update
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "jetstack" chart repository
...Successfully got an update from the "aliyun" chart repository
...Successfully got an update from the "stable" chart repository
Update Complete. ⎈ Happy Helming!⎈ 

# list helm repo
[root@CentOS001 ~]# helm repo list
NAME    	URL                                                   
stable  	http://mirror.azure.cn/kubernetes/charts              
aliyun  	https://kubernetes.oss-cn-hangzhou.aliyuncs.com/charts
jetstack	https://charts.jetstack.io                            

# search chart
[root@CentOS001 ~]# helm search repo nginx
NAME                       	CHART VERSION	APP VERSION	DESCRIPTION                                       
aliyun/nginx-ingress       	0.9.5        	0.10.2     	An nginx Ingress controller that uses ConfigMap...
aliyun/nginx-lego          	0.3.1        	           	Chart for nginx-ingress-controller and kube-lego  
stable/nginx-ingress       	1.41.3       	v0.34.1    	DEPRECATED! An nginx Ingress controller that us...
stable/nginx-ldapauth-proxy	0.1.6        	1.13.5     	DEPRECATED - nginx proxy with ldapauth            
stable/nginx-lego          	0.3.1        	           	Chart for nginx-ingress-controller and kube-lego  
aliyun/gcloud-endpoints    	0.1.0        	           	Develop, deploy, protect and monitor your APIs ...
stable/gcloud-endpoints    	0.1.2        	1          	DEPRECATED Develop, deploy, protect and monitor..
```





# Common Troubleshooting Tips

```bash
kubectl get nodes
kubectl get ds -n kube-system
kubectl get pod
kubectl get pods -n kube-system
kubectl get pods -n kube-system -o wide
kubectl logs weave-net-ldsgl  -n kube-system weave-npc
kubectl describe pod auth-54d7667c5d-sgrt8
systemctl status kubelet
journalctl -f -u kubelet
# If the init container failed, subsequent container initilization just pending there, no logs from below commands
kubectl logs auth-54d7667c5d-dnslv
kubectl logs scan-687c4bfddd-w5fbk  --previous
# check why init container failed, lead to subsequent container can not be initialized
kubectl logs scan-687c4bfddd-w5fbk  -c db-init 
```

