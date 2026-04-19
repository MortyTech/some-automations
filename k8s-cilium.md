# Deploy Kubernetes with Kubeadm, Containerd, Cilium CNI and Cilium Ingress

<div data-full-width="true"><figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2Fj2LS6IKonuR4dmlslPyf%2Fimage.png?alt=media&#x26;token=0119f717-28c3-47b8-bef8-1db0f4e30b41" alt="" width="188"><figcaption></figcaption></figure></div>

### VM and IP Plan

I have 2 node, one master and one worker

| IP          | Role   | Hostname |
| ----------- | ------ | -------- |
| 10.11.119.4 | Worker | kw       |
| 10.11.119.2 | Master | km       |

first of all we update and upgrade our 2 node

```
sudo apt update ; sudo apt upgrade ; reboot
```

### Kernel Upgrade and tune

now we upgrade the kernel to latest Long-term release

```
wget https://kernel.ubuntu.com/~kernel-ppa/mainline/v6.1.53/amd64/linux-headers-6.1.53-060153-generic_6.1.53-060153.202309130436_amd64.deb
wget https://kernel.ubuntu.com/~kernel-ppa/mainline/v6.1.53/amd64/linux-headers-6.1.53-060153_6.1.53-060153.202309130436_all.deb
wget https://kernel.ubuntu.com/~kernel-ppa/mainline/v6.1.53/amd64/linux-image-unsigned-6.1.53-060153-generic_6.1.53-060153.202309130436_amd64.deb
wget https://kernel.ubuntu.com/~kernel-ppa/mainline/v6.1.53/amd64/linux-modules-6.1.53-060153-generic_6.1.53-060153.202309130436_amd64.deb
sudo dpkg -i *.deb
sudo reboot
```

make some kernel tune and config :&#x20;

```
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
```

```
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
sudo modprobe overlay
sudo modprobe br_netfilter
```

```
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
```

```
sudo sysctl --system
```

### Install ContainerD

To run containers in Pods, Kubernetes uses a container runtime. \
so we are going to install containerd

**Step 1: Installing containerd**

Download the latest `containerd-<VERSION>-linux-amd64.tar.gz` archive from <https://github.com/containerd/containerd/releases> , and extract it under `/usr/local`:\ <mark style="color:orange;">Do not forgot run command by root for extracting into /usr</mark>

```
wget https://github.com/containerd/containerd/releases/download/v1.6.24/containerd-1.6.24-linux-amd64.tar.gz
tar Cxzvf /usr/local containerd-1.6.24-linux-amd64.tar.gz
```

we intend to start containerd via systemd :&#x20;

```
mkdir -p /usr/local/lib/systemd/system/
wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service -O /usr/local/lib/systemd/system/containerd.service
systemctl daemon-reload
systemctl enable --now containerd
```

**Step 2: Installing runc**

Download the `runc.<ARCH>` binary from <https://github.com/opencontainers/runc/releases> , verify its sha256sum, and install it as `/usr/local/sbin/runc`

```
wget https://github.com/opencontainers/runc/releases/download/v1.1.9/runc.amd64
install -m 755 runc.amd64 /usr/local/sbin/runc
```

**Step 3: Installing CNI plugins**

Download the `cni-plugins-linux-amd64-<VERSION>.tgz` archive from <https://github.com/containernetworking/plugins/releases> , verify its sha256sum, and extract it under `/opt/cni/bin`:

```
wget https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz
mkdir -p /opt/cni/bin
tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.3.0.tgz
```

### **Configuring the `systemd` cgroup driver**

To use the `systemd` cgroup driver in `/etc/containerd/config.toml` with `runc`:&#x20;

```
mkdir -p /etc/containerd/
containerd config default | tee /etc/containerd/config.toml
```

```
sudo sed -i 's/            SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml
```

```
cat /etc/containerd/config.toml | grep SystemdCgroup
```

you should see the `SystemdCgroup` is `true`

```shell
sudo systemctl restart containerd
```

### Identify the cgroup version on Linux Nodes

To check which cgroup version your distribution uses, run the `stat -fc %T /sys/fs/cgroup/` command on the node:

```shell
stat -fc %T /sys/fs/cgroup/
```

For cgroup v2, the output is `cgroup2fs`.

For cgroup v1, the output is `tmpfs.`

we should see `cgroup2fs`

### Interacting with containerd via CLI

The [`nerdctl`](https://github.com/containerd/nerdctl) tool provides stable and human-friendly user experience.\
`nerdctl` is a Docker-compatible CLI for [containerd](https://containerd.io/).

```
wget https://github.com/containerd/nerdctl/releases/download/v1.5.0/nerdctl-1.5.0-linux-amd64.tar.gz
tar Cxzvvf /usr/local/bin nerdctl-1.5.0-linux-amd64.tar.gz
nerdctl --version
```

#### Debugging Kubernetes

To list local Kubernetes containers:

```
nerdctl --namespace k8s.io ps -a
```

### install and Configure Kubernetes Controlplane <a href="#heading-configure-kubernetes-controlplane" id="heading-configure-kubernetes-controlplane"></a>

Once, the container runtime is installed successfully on both nodes, we are now ready to configure our Kubernetes Controlplane

* `kubeadm`: the command to bootstrap the cluster.
* `kubelet`: the component that runs on all of the machines in your cluster and does things like starting pods and containers.
* `kubectl`: the command line util to talk to your cluster.

{% hint style="info" %}
Installing kubeadm, kubelet and kubectl on <mark style="color:yellow;">Master</mark> node and just kubeadm, kubelet on <mark style="color:yellow;">Worker</mark> node
{% endhint %}

now we going to Install the necessary tools dependencies with the following command:

```
sudo apt install curl gnupg2 net-tools software-properties-common apt-transport-https ca-certificates -y
```

```
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

```
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

```
sudo systemctl enable kubelet --now
```

{% hint style="warning" %}
Initialize the Kubernetes Cluster just on Master
{% endhint %}

```
kubeadm init --skip-phases=addon/kube-proxy --upload-certs --pod-network-cidr=10.1.0.0/16 --apiserver-advertise-address 10.11.119.2
```

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2FUyAIbWyeWTIylEukQcLu%2Fimage.png?alt=media&#x26;token=9be5d11b-4848-4937-a8e1-100849aac445" alt="" width="563"><figcaption></figcaption></figure>

on master node

```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

We need to copy this `kubeadm join` command and apply this to our `kw` worker node to join the cluster. do not forget you have your own join command&#x20;

on worker node&#x20;

```
kubeadm join 10.11.119.2:6443 --token hw2p1g.cwqx2swnj5coba04 \
        --discovery-token-ca-cert-hash sha256:7dc1796f82eeb8d95c3387ae9699ecd99e8f097b2afe5a98943f861ffda4
```

on master node&#x20;

```
kubectl get nodes
NAME   STATUS     ROLES           AGE   VERSION
km     NotReady   control-plane   11m   v1.28.2
kw     NotReady   <none>          22s   v1.28.2
```

We can see the Nodes are in a **NotReady** state, this is because we have not yet implemented the [Pod Networking CNI plugin](https://github.com/containernetworking/cni#3rd-party-plugins) yet. For this experiment, we shall be using [**Cilium**](https://kubernetes.io/docs/tasks/administer-cluster/network-policy-provider/cilium-network-policy/) as our networking solution.

### kubectl bash auto completion

for better going forward with kubectl cli, install kubectl bash completion&#x20;

```bash
kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null
sudo chmod a+r /etc/bash_completion.d/kubectl
```

### eBPF FS

{% embed url="<https://ebpf.io/>" %}

Before we install Cilium CLI, let’s prep the node by mounting the eBPF filesystem on all three nodes.

```
sudo mount bpffs -t bpf /sys/fs/bpf
```

since this is not a typical filesystem and it's not appropriate to add it to `/etc/fstab`. In such cases, you may want to create a custom systemd service or a startup script that runs the `mount` command during the boot process. so we are using the `@reboot` directive in cronjob to have it executed at system startup. i added this cronjob on user ubuntu with sudo.

```
crontab -e
```

```
@reboot sleep 10 && sudo mount bpffs -t bpf /sys/fs/bpf
```

### install helm3

no we need to install helm , install latest helm 3 by below:

```
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
bash get_helm.sh
```

### install Cilium

<figure><img src="https://camo.githubusercontent.com/bccdb572f063ee200a0f71bde7d58a2171909402548644b9dfe0572744125015/68747470733a2f2f63646e2e6a7364656c6976722e6e65742f67682f63696c69756d2f63696c69756d406d61696e2f446f63756d656e746174696f6e2f696d616765732f6c6f676f2d6461726b2e706e67" alt=""><figcaption></figcaption></figure>

Cilium is an open source, cloud native solution for providing, securing, and observing network connectivity between workloads, fueled by the revolutionary Kernel technology eBPF

add cilium repo and install it:

```
helm repo add cilium https://helm.cilium.io/
```

because I want Cilium to take care of all of the networking components. There’s no point in having a slower kube-proxy service. as we initialized our k8s controlplane by `--skip-phases=addon/kube-proxy`  Therefore, the Cilium agent needs to be made aware of this information with the following configuration:

```
API_SERVER_IP=10.11.119.2
API_SERVER_PORT=6443
helm install  cilium cilium/cilium --version 1.14.2 \
    --namespace kube-system \
    --set nodePort.enabled=true \
    --set kubeProxyReplacement=true \
    --set k8sServiceHost=${API_SERVER_IP} \
    --set k8sServicePort=${API_SERVER_PORT} \
    --set ingressController.enabled=true \
    --set ingressController.loadbalancerMode=shared \
    --set ipam.operator.clusterPoolIPv4PodCIDRList=10.1.0.0/16 \
    --set ipv4NativeRoutingCIDR=10.1.0.0/16 \
    --set ipv4.enabled=true \
    --set loadBalancer.mode=dsr \
    --set tunnel=disabled \
    --set autoDirectNodeRoutes=true
```

```
You have successfully installed Cilium with Hubble.

Your release version is 1.14.2.
```

Cilium uses the standard [Kubernetes Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) resource definition, with an `ingressClassName` of `cilium`. This can be used for path-based routing and for TLS termination.

### Validate the Setup

After deploying Cilium with helm, we can first validate that the Cilium agent is running in the desired mode:

```
kubectl -n kube-system exec ds/cilium -- cilium status | grep KubeProxyReplacement
KubeProxyReplacement:    True   [ens192 10.11.119.4 (Direct Routing)]
```

```
kubectl -n kube-system exec ds/cilium -- cilium status --verbose | grep -A 17 "KubeProxyReplacement Details:"

KubeProxyReplacement Details:
  Status:                 True
  Socket LB:              Enabled
  Socket LB Tracing:      Enabled
  Socket LB Coverage:     Full
  Devices:                ens192 10.11.119.4 (Direct Routing)
  Mode:                   DSR
  Backend Selection:      Random
  Session Affinity:       Enabled
  Graceful Termination:   Enabled
  NAT46/64 Support:       Disabled
  XDP Acceleration:       Disabled
  Services:
  - ClusterIP:      Enabled
  - NodePort:       Enabled (Range: 30000-32767)
  - LoadBalancer:   Enabled
  - externalIPs:    Enabled
  - HostPort:       Enabled
[...]
```

### About DSR

{% embed url="<https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/#direct-server-return-dsr>" %}

### install Cilium cli

for verifying better and forward for install easily more  component like Hubble we install `cilium cli` i add the little install script to install it:

```
nano cilium-install.sh
```

add below to it&#x20;

```
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
```

```
bash cilium-install.sh
```

```
cilium status

    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    disabled (using embedded mode)
 \__/¯¯\__/    Hubble Relay:       disabled
    \__/       ClusterMesh:        disabled

DaemonSet              cilium             Desired: 2, Ready: 2/2, Available: 2/2
Deployment             cilium-operator    Desired: 2, Ready: 2/2, Available: 2/2
Containers:            cilium             Running: 2
                       cilium-operator    Running: 2
Cluster Pods:          4/4 managed by Cilium
Helm chart version:    1.14.2
Image versions         cilium-operator    quay.io/cilium/operator-generic:v1.14.2@sha256:52f70250dea22e506959439a7c4ea31b10fe8375db62f5c27ab746e3a2af866d: 2
                       cilium             quay.io/cilium/cilium:v1.14.2@sha256:6263f3a3d5d63b267b538298dbeb5ae87da3efacf09a2c620446c873ba807d35: 2
```

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2FJELjPRTPAjcPGR94RzKO%2Fimage.png?alt=media&#x26;token=64862a50-1b5e-46b0-9c4d-b476e2b8aee3" alt=""><figcaption></figcaption></figure>

### About Cilium Ingress

{% embed url="<https://docs.cilium.io/en/stable/network/servicemesh/ingress/#kubernetes-ingress-support>" %}

### Ingress Controller and Hubble

Enable the Hubble UI by running the following command:

```
cilium hubble enable
cilium hubble enable --ui
```

for access to Hubble UI we edit the hubble-ui service type to NodePort

```
kubectl edit service/hubble-ui -n kube-system
```

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2F4LFXznwhqn50MgwhUvGn%2Fimage.png?alt=media&#x26;token=73e21cc8-2d52-4bdc-ab11-fa4faef678e1" alt=""><figcaption></figcaption></figure>

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2F8gGYAMCB4uKulCXlSJCN%2Fimage.png?alt=media&#x26;token=1ee7b8bc-6684-4b48-a2f9-2121bbc942ea" alt=""><figcaption></figcaption></figure>

as we can see it listen on port 32284 on nodeport\
so we can open it on master IP and port\
i have access directly on network 10.11.119.0/24, so i can open it on my browser, if you dosent have access to this network, you can use ssh socks5 by `ssh -D ubuntu@10.11.119.2`

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2F2TNkws9L707khCIuCjPo%2Fimage.png?alt=media&#x26;token=3b6e9476-0098-46f7-98c8-8e35caf02944" alt=""><figcaption></figcaption></figure>

We will back to Hubbel soon ...

now its time to test our cluster with cilium service and ingress , but there is still one thing left to configure. since the ingress controller is a service and default its on ClusterIP type, so we edit the service:

```
kubectl edit service/cilium-ingress -n kube-system
```

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2Fwum1mHabUGAFXtyOnezx%2Fimage.png?alt=media&#x26;token=a411f8fb-b226-4f60-b371-be2d93bbc1fe" alt=""><figcaption></figcaption></figure>

```
kubectl get svc -A

NAMESPACE     NAME             TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)                      AGE
default       kubernetes       ClusterIP      10.96.0.1        <none>        443/TCP                      12h
kube-system   cilium-ingress   LoadBalancer   10.104.223.159   10.11.119.2   80:32284/TCP,443:31923/TCP   11h
```

### Deploy pod and service

create the pod and service yaml file:

```
kind: Pod
apiVersion: v1
metadata:
  name: foo-app
  labels:
    app: foo
spec:
  containers:
    - name: foo-app
      image: 'kicbase/echo-server:1.0'
---
kind: Service
apiVersion: v1
metadata:
  name: foo-service
spec:
  selector:
    app: foo
  ports:
    - port: 8080
---
kind: Pod
apiVersion: v1
metadata:
  name: bar-app
  labels:
    app: bar
spec:
  containers:
    - name: bar-app
      image: 'kicbase/echo-server:1.0'
---
kind: Service
apiVersion: v1
metadata:
  name: bar-service
spec:
  selector:
    app: bar
  ports:
    - port: 8080
```

```
kubectl apply -f service-pod.yaml
pod/foo-app created
service/foo-service created
pod/bar-app created
service/bar-service created
```

### Create DNS name record

i added the name record to `/etc/hosts` file for testing ingrss&#x20;

```
10.11.119.2     cilium.mortytech.ir
```

Cilium uses the standard [Kubernetes Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) resource definition, with an `ingressClassName` of `cilium`.

### Create Ingress rule

create ingress-rule yaml file :&#x20;

```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-cilium
spec:
  ingressClassName: cilium
  rules:
  - host: cilium.mortytech.ir
    http:
        paths:
          - pathType: Prefix
            path: /foo
            backend:
              service:
                name: foo-service
                port:
                  number: 8080
          - pathType: Prefix
            path: /bar
            backend:
              service:
                name: bar-service
                port:
                  number: 8080
```

```
kubectl get ingress

NAME             CLASS    HOSTS                 ADDRESS   PORTS   AGE
ingress-cilium   cilium   cilium.mortytech.ir             80      14s
```

```
kubectl describe ingress

Name:             ingress-cilium
Labels:           <none>
Namespace:        default
Address:
Ingress Class:    cilium
Default backend:  <default>
Rules:
  Host                 Path  Backends
  ----                 ----  --------
  cilium.mortytech.ir
                       /foo   foo-service:8080 (10.0.1.24:8080)
                       /bar   bar-service:8080 (10.0.1.247:8080)
Annotations:           <none>
Events:                <none>
```

now we can verify ingress and its result

```
curl cilium.mortytech.ir/bar

Request served by bar-app

HTTP/1.1 GET /bar

Host: cilium.mortytech.ir
Accept: */*
```

```
curl cilium.mortytech.ir/foo

Request served by foo-app

HTTP/1.1 GET /foo

Host: cilium.mortytech.ir
Accept: */*
```

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2FllaQdr1RZurKFX0v5G4o%2Fimage.png?alt=media&#x26;token=af44e379-ecd9-4f84-8540-876b2462d22b" alt=""><figcaption></figcaption></figure>

The beauty of their work by the setup of pods ,services and ingress is  we can observe any request that reaches our Ingress using Hubble.

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2FuTqyKM3DaIzmD2tdQPIs%2Fimage.png?alt=media&#x26;token=b163f780-bacc-4c80-a862-a4659620759e" alt=""><figcaption></figcaption></figure>
