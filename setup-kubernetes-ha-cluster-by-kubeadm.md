# Setup Kubernetes HA Cluster by Kubeadm

***

### Our IP Plan for Kubernetes Cluster:

<table><thead><tr><th width="141" align="center">Server</th><th align="center">IP</th><th>comment</th><th align="center">RAM CPU DISK</th></tr></thead><tbody><tr><td align="center">Gateway</td><td align="center">192.168.0.1</td><td>Its Gateway !</td><td align="center">-</td></tr><tr><td align="center">M1</td><td align="center">192.168.0.11</td><td>definitely</td><td align="center">C8 R8 D25</td></tr><tr><td align="center">M2</td><td align="center">192.168.0.12</td><td>definitely</td><td align="center">C8 R8 D25</td></tr><tr><td align="center">M3</td><td align="center">192.168.0.13</td><td>definitely</td><td align="center">C8 R8 D25</td></tr><tr><td align="center">W1</td><td align="center">192.168.0.21</td><td>maybe not plan</td><td align="center">-</td></tr><tr><td align="center">W2</td><td align="center">192.168.0.22</td><td>maybe not plan</td><td align="center">-</td></tr><tr><td align="center">B1</td><td align="center">192.168.0.9</td><td>definitely</td><td align="center">C4 R4 D15</td></tr><tr><td align="center">VIP (VRRP)</td><td align="center">192.168.0.10</td><td>definitely</td><td align="center">-</td></tr></tbody></table>

run openstack command for launching VM :

```
openstack server create --image "Ubuntu 20.04 Original" --boot-from-volume 15 \
--key-name AspireV5 --flavor C4R4 \
--nic net-id=c5ca5a78-f94d-46a1-b4fa-cc76fbe9e7c7,v4-fixed-ip=192.168.0.9 B1

openstack server create --image "Ubuntu 20.04 Original" --boot-from-volume 25 \
--key-name AspireV5 --flavor C8R8D0 \
--nic net-id=c5ca5a78-f94d-46a1-b4fa-cc76fbe9e7c7,v4-fixed-ip=192.168.0.11 M1


openstack server create --image "Ubuntu 20.04 Original" --boot-from-volume 25 \
--key-name AspireV5 --flavor C8R8D0 \
--nic net-id=c5ca5a78-f94d-46a1-b4fa-cc76fbe9e7c7,v4-fixed-ip=192.168.0.12 M2


openstack server create --image "Ubuntu 20.04 Original" --boot-from-volume 25 \
--key-name AspireV5 --flavor C8R8D0 \
--nic net-id=c5ca5a78-f94d-46a1-b4fa-cc76fbe9e7c7,v4-fixed-ip=192.168.0.13 M3
```

connecting to B1 for manage and ssh to other nodes:

```
ssh ubuntu@86.104.44.198 -p 2222
```

add the host and IP to `/etc/hosts` to all node even B1

```
192.168.0.10    vipk8s
192.168.0.9     b1
192.168.0.13    M3
192.168.0.12    M2
192.168.0.11    M
```

{% hint style="warning" %}
becase of openstack port security the vrrp floating ip would not work, so we should turn off the port security of M1 and M2 and M3&#x20;
{% endhint %}

create tmux session and slpit it to 3 pane for running concurrent command by `setw synchronize-panes`

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2FgDG2lUF9tXPKdYfAzvmS%2Fimage.png?alt=media&#x26;token=d9b5595b-0fcd-468b-8c6b-f7258dc4c284" alt=""><figcaption></figcaption></figure>

run below command on all node by tmux 😊

### HighAvailable Loadbalancer

first install vrrp and loadbalancer :

```
apt install haproxy keepalived -y
```

for config HAProxy, append this config to `/etc/haproxy/haproxy.cfg`&#x20;

```
frontend kubernetes
    bind *:8443
    mode tcp
    default_backend kubernetes-backend

backend kubernetes-backend
    mode tcp
    balance roundrobin
    server server1 192.168.0.11:6443 check
    server server2 192.168.0.12:6443 check
    server server3 192.168.0.13:6443 check
```

create keepalived chek script : `nano /etc/keepalived/check_apiserver.sh`

```
#!/bin/sh
APISERVER_VIP=192.168.0.10
APISERVER_DEST_PORT=8443

errorExit() {
    echo "*** $*" 1>&2
    exit 1
}

curl --silent --max-time 2 --insecure https://localhost:${APISERVER_DEST_PORT}/ -o /dev/null || errorExit "Error GET https://localhost:${APISERVER_DEST_PORT}/"
if ip addr | grep -q ${APISERVER_VIP}; then
    curl --silent --max-time 2 --insecure https://${APISERVER_VIP}:${APISERVER_DEST_PORT}/ -o /dev/null || errorExit "Error GET https://${APISERVER_VIP}:${APISERVER_DEST_PORT}/"
fi
```

make the script executable : `chmod +x /etc/keepalived/check_apiserver.sh`

Configure IP forwarding and non-local binding

To enable Keepalived service to forward network packets to the backend servers, you need to enable IP forwarding. Run this command on all Master nodes :&#x20;

```
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
echo "net.ipv4.ip_nonlocal_bind = 1" >> /etc/sysctl.conf
sysctl -p
```

config keepalived itself : `nano /etc/keepalived/keepalived.conf`

```
# Define the script used to check if haproxy is still working
vrrp_script check_apiserver {
  script "/etc/keepalived/check_apiserver.sh"
  interval 3
  weight -2
  fall 10
  rise 2
}
# Configuration for Virtual Interface
vrrp_instance VI_1 {
    state SLAVE
    interface ens3
    virtual_router_id 151
    priority 254
    authentication {
        auth_type PASS
        auth_pass k8sStage
    }
    virtual_ipaddress {
        192.168.0.10/24
    }
    track_script {
        check_apiserver
    }
}
```

{% hint style="danger" %}
Only two parameters of this file need to be changed for master-2 & 3 nodes. **State** will become **SLAVE** for master 2 and 3, priority will be 254 and 253 respectively
{% endhint %}

```
systemctl enable keepalived --now
systemctl enable haproxy --now
systemctl restart keepalived
systemctl restart haproxy
```

now we should have listen port 8443 on all nodes and IP 192.168.0.10 on Master1 :&#x20;

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2Fz2QkSBnD83kYllm6YQyq%2Fimage.png?alt=media&#x26;token=7226b44f-40fd-4912-be3a-a6cc4d67938b" alt=""><figcaption></figcaption></figure>

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2FXZYUYAmJVI60a4cHcQGf%2Fimage.png?alt=media&#x26;token=a6653ba7-f25c-48c1-a4b0-f4d6aa00cc6e" alt=""><figcaption></figcaption></figure>

we should make the swap off:&#x20;

```
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

### Install containerd

now we Install and preconfigure Container Run Time (containerd) on all Master :&#x20;

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2F71RkxxYvPUwpdHtP18o1%2Fimage.png?alt=media&#x26;token=d93ad8b5-dc80-4fb5-b853-f9cbd47a7a67" alt="" width="290"><figcaption></figcaption></figure>

First, load two modules in the current running environment and configure them to load on boot

```
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

Configure required sysctl to persist across system reboots

```
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system
```

now :&#x20;

```
sudo apt-get install -y apt-transport-https ca-certificates curl
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt install containerd.io -y
```

Create a new directory for *containerd* with:&#x20;

```
sudo mkdir -p /etc/containerd
```

Generate the configuration file with:&#x20;

```
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo systemctl enable containerd --now
```

Set the cgroup driver for runc to systemd, which is required for the kubelet.

Change the value for `SystemCgroup` from `false` to `true`.

```
sudo sed -i 's/            SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml
```

Restart containerd with the new configuration

```
sudo systemctl restart containerd 
```

***

### Now, let’s install kubeadm , kubelet and kubectl in the next step

```
sudo mkdir -p /etc/apt/keyrings
```

Download the Google Cloud public signing key:

```shell
curl -fsSL https://dl.k8s.io/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
```

Add the Kubernetes apt repository:

```shell
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

Update apt package index, install kubelet, kubeadm and kubectl, and pin their version:

```shell
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

Run following systemctl command to enable kubelet service on all nodes

```
sudo systemctl enable kubelet --now
```

{% hint style="warning" %}
Initialize the Kubernetes Cluster just from Master1\
this means run kubeadm init on master1
{% endhint %}

Now move to first master node / control plane and issue the following command:&#x20;

```
kubeadm init --control-plane-endpoint "192.168.0.10:8443" --pod-network-cidr 192.168.1.0/24 --upload-certs --cri-socket unix:///var/run/containerd/containerd.sock
```

On a successful kubeadm initialization, you should get an output with kubeconfig file location and the join command with the token as shown below. Copy that and save it to the file. we will need it

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2FDoOyG7idZeshK9nQvEKX%2Fimage.png?alt=media&#x26;token=4cd2b708-997f-430d-b46f-1106bf26c858" alt=""><figcaption></figcaption></figure>

Use the following commands from the output to create the kubeconfig in master so that you can use kubectl to interact with cluster API

```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Now, verify the kubeconfig by executing the following kubectl command to list all the pods in the `kube-system` namespace.

```
kubectl get po -n kube-system
```

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2FqywhZDNUWLfAWy8R635Q%2Fimage.png?alt=media&#x26;token=e3ebacee-b233-4b3f-8465-71e5787bf1f5" alt=""><figcaption></figcaption></figure>

You should see the following output. You will see the two Coredns pods in a pending state. It is the expected behavior. Once we install the network plugin, it will be in a running state

You verify all the cluster component health statuses using the following command.

```
kubectl get --raw='/readyz?verbose'
```

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2FWVLQbEE2TP9t9HFw6sF6%2Fimage.png?alt=media&#x26;token=90ea3008-bd1d-4e40-9321-bee698b6f55e" alt=""><figcaption></figcaption></figure>

You can get the cluster info using the following command.

```
kubectl cluster-info 
```

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2FbE84gfM9vMxKmVZWTaj2%2Fimage.png?alt=media&#x26;token=6f273f46-92e0-471d-8afc-d4e5988f1dac" alt=""><figcaption></figcaption></figure>

### Install Calico Network Plugin for Pod Networking

Execute the following command to install the calico network plugin on the cluster:&#x20;

```
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/master/manifests/calico.yaml
```

After a couple of minutes, if you check the pods in kube-system namespace, you will see calico pods and running CoreDNS pods.\
Once the pod network is deployed successfully, add remaining two master nodes to cluster. Just copy the command for master node to join the cluster from the output and paste it on Master2 and Master3, example is shown below:&#x20;

```
kubeadm join 192.168.0.10:8443 --token fmpvca.07h2xlqu7esd9gn8 \
        --discovery-token-ca-cert-hash sha256:a6a5fa1129df2f96e64b7b4cff20030b5fb97f2664a65a81dae33fc44ebf7ab6 \
        --control-plane --certificate-key a9e854a8f6b85ffbfc0f15f4bb8d728f114fecc2f7db7c38025509952a3cb564
```

On successful execution, you will see the output saying, “This node has joined the cluster”

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2FZ8njBhUHwgwIth0sMGP7%2Fimage.png?alt=media&#x26;token=7544f7d4-26b5-4a31-89ce-052ffe78a7b6" alt=""><figcaption></figcaption></figure>

after add the master 2 and 3 with `kubeadm join` now run the command for administering new cluster node, run below on user and root on master 2 and 3, master 1 has been raned before :&#x20;

```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

now we have 3 master node we can verify the nodes status from kubectl command, if successful kube config file generated before we can run **kubectl** on all master nodes:

```
kubectl get nodes
```

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2F8Ykbn9j4WLJFaeEBUQfv%2Fimage.png?alt=media&#x26;token=0c977d2e-347a-43a0-b61d-ddb415962067" alt=""><figcaption></figcaption></figure>

after few minutes we have healthy cluster !

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2FNLHRzq3rsAXx00zVhqcV%2Fimage.png?alt=media&#x26;token=7d4b1940-662e-48e6-bfad-e545723c17e7" alt=""><figcaption></figcaption></figure>

{% hint style="warning" %}
By default, apps won’t get scheduled on the master node. If you want to use the master node for scheduling apps, taint the master node.
{% endhint %}

```
kubectl taint nodes --all node-role.kubernetes.io/master-

OR

kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

### **Test Highly available Kubernetes cluster**

Let’s try to connect to the cluster from B1 node\
we should install `kubectl` command on it:&#x20;

```
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://dl.k8s.io/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get install -y kubectl
```

we should copy the /etc/kubernetes/admin.conf from master node, i scp this file, you should run scp command by root to compy or choose other way :

```
mkdir -p $HOME/.kube
scp m1:/etc/kubernetes/admin.conf /home/ubuntu/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Now run “kubectl get nodes” command:

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2FzwiR8i3onsTQUuPDPs0e%2Fimage.png?alt=media&#x26;token=157d8208-8d51-438f-8f41-541b1477a7e7" alt=""><figcaption></figcaption></figure>

now for test the VRRP and cluster HA i run two watch command, one in B1 for watching `kubectl get nodes` command continuously and second on all master node for watching ip -br a to watch the floating VRRP IP that change the node and interface.\
if the VRRP IP correctly changed on M2 ***(because is has upper priority in keepalived)*** and the `kubectl` get node get no interrupted this means everything is going on well !

### Setup Kubernetes Metrics Server <a href="#setup-kubernetes-metrics-server" id="setup-kubernetes-metrics-server"></a>

Kubeadm doesn’t install metrics server component during its initialization. We have to install it separately.\
To verify this, if you run the top command, you will see the Metrics API not available error.

```
kubectl top nodes
error: Metrics API not available
```

To install the metrics server, execute the following metric server manifest file

```
kubectl apply -f https://raw.githubusercontent.com/techiescamp/kubeadm-scripts/main/manifests/metrics-server.yaml
```

it takes a minute for you to see the node and pod metrics using the top command.

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2FdYuWhGmtSrlgWlHkxqCl%2Fimage.png?alt=media&#x26;token=a90eb6da-5b76-4b41-be62-b5c485d505a2" alt=""><figcaption></figcaption></figure>

### Deploy A Sample Nginx Application <a href="#deploy-a-sample-nginx-application" id="deploy-a-sample-nginx-application"></a>

Now that we have all the components to make the cluster and applications work, let’s deploy a sample Nginx application and see if we can access it over a NodePort.\
Create an Nginx deployment. Execute the following directly on the command line. It deploys the pod in the default namespace.

```
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 3 
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80      
EOF
```

Expose the Nginx deployment on a NodePort 32000

```
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector: 
    app: nginx
  type: NodePort  
  ports:
    - port: 80
      targetPort: 80
      nodePort: 32000
EOF
```

Check the pod status using the following command.

```
kubectl get pods
```

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2F0Deb2gZM9v6W6o3McUcS%2Fimage.png?alt=media&#x26;token=f5ffc12e-ba89-4ba1-b357-342f6f1d1403" alt=""><figcaption></figcaption></figure>

```
kubectl get service
```

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2FF06yfqpJzEecGseAsLyA%2Fimage.png?alt=media&#x26;token=9abbaa99-065b-471c-b411-90df4e8e5d08" alt=""><figcaption></figcaption></figure>

Once the deployment is up, you should be able to access the Nginx home page on the allocated NodePort. i install links cli browser to test the nginx welcome page, but you can test it by anyway you like or even curl. since we have scheduled the pods on our Master nodes like as a worker node, we able to access nginx on port 3200 by master IPs. and also we set the **`replica set`** number to 3, so we have 3 nginx pod on all Master/Worker nods :&#x20;

```bash
ubuntu@b1:~$ curl 192.168.0.13:32000
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

ubuntu@b1:~$ curl 192.168.0.12:32000
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

ubuntu@b1:~$ curl 192.168.0.11:32000
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>
```

### Deploy the Kubernetes Dashboard

Dashboard is a web-based Kubernetes user interface. You can use Dashboard to deploy containerized applications to a Kubernetes cluster

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2FdktDwcUxp1eTzdrJDyM9%2Fimage.png?alt=media&#x26;token=b06d897b-82d5-48fd-9770-196e8ca6876f" alt=""><figcaption></figcaption></figure>

The Dashboard UI is not deployed by default. To deploy it, run the following command:

```
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
```

in a ordinary Kubernetes deployment the api address is accessible from outside or by VPN or controlled firewall rules, but since in my deployment, my api address is an private address that can not behind NAT, so i would change the config of Kube dashboard to make it listen on my nat ip.

```
kubectl edit service/kubernetes-dashboard -n kubernetes-dashboard
```

the config is opened by vim editor by default and its like this :&#x20;

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2F5tOvnMHJRzYmNUq5kZ2V%2Fimage.png?alt=media&#x26;token=e1218485-d327-4ff6-b8cc-a16288156fb4" alt=""><figcaption></figcaption></figure>

Once the file is opened, change the type of service from ClusterIP to NodePort and save the file as shown below. By default, the service is only available internally to the cluster (ClusterIP) but changing to NodePort exposes the service to the outside.

{% hint style="danger" %}
Setting the service type to NodePort allows all IPs (inside or outside of) the cluster to access the service.
{% endhint %}

```
# Updated the type to NodePort in the service.
  ports:
  - port: 443
    protocol: TCP
    targetPort: 8443
  selector:
    k8s-app: kubernetes-dashboard
  sessionAffinity: None
  type: NodePort
status:
  loadBalancer: {}
```

after edit and change service dashboard we verify the kubernetes-dashboard service has the correct type by running the `kubectl get svc --all-namespace` command. You will now notice that the service type has changed to NodePort, and the service exposes the pod’s internal TCP port 30989 using the outside TCP port of 443.

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2FUXuNhfsEIz5SutUlsehk%2Fimage.png?alt=media&#x26;token=1b6ad6bb-0ec9-40c3-86ee-d83b21d8aa59" alt=""><figcaption></figcaption></figure>

Now we can open the dashboard by the VRRP Floating IP and mapped TCP port 30989.\
I use SSH dynamic port forwarding (SOCKS5) to access the IP and port of the dashboard

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2F7dnTuLJl7uGYcf1Q32y4%2Fimage.png?alt=media&#x26;token=66a5f28c-abf4-452c-b6c4-69fafac769e2" alt=""><figcaption></figcaption></figure>

Now to login properly into the Kubernetes dashboard we need to create a service account.\
create a service account using `kubectl create serviceaccount`

```
kubectl create serviceaccount dashboard -n default
```

Create the `clusterrolebinding` rule using the `kubectl create clusterrolebinding` command assigning the `cluster-admin` role to the previously-created service account to have full access across the entire cluster.

```
kubectl create clusterrolebinding dashboard-admin -n default --clusterrole=cluster-admin --serviceaccount=default:dashboard
```

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2F7oHCzxXhSxKpOYGF2BWc%2Fimage.png?alt=media&#x26;token=10a87e22-c019-46a9-b4a6-80ce862c747e" alt=""><figcaption></figcaption></figure>

Since In Kubernetes 1.24, ServiceAccount token secrets are no longer automatically generated, we need to create it manually :&#x20;

```
kubectl create token dashboard
```

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2FLxSISiphg9g1XT20Sf6g%2Fimage.png?alt=media&#x26;token=c8c45c00-2a64-4406-9723-57725a15adeb" alt=""><figcaption></figcaption></figure>

note that these tokens are valid for one hour, we can create longer token age by specify\
&#x20;`--duration=` , be notice the maximum expiration is 720h,&#x20;

{% hint style="danger" %}
Unauthorized (401): You have been logged out because your token has expired.
{% endhint %}

```
kubectl create token dashboard --duration=488h --output yaml
apiVersion: authentication.k8s.io/v1
kind: TokenRequest
metadata:
  creationTimestamp: "2023-07-27T08:38:45Z"
  name: dashboard
  namespace: default
spec:
  audiences:
  - https://kubernetes.default.svc.cluster.local
  boundObjectRef: null
  expirationSeconds: 1756800
status:
  expirationTimestamp: "2023-08-16T16:38:45Z"
  token: eyJhb...
```

now we using this token to login, paste the token has been generated into token box and press Sign in

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2FQtg32rLwy78xqZzlQ38T%2Fimage.png?alt=media&#x26;token=d4325d9f-0571-454c-a0d4-ede220b7bfd5" alt=""><figcaption></figcaption></figure>

<figure><img src="https://1415563701-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F5z88OE2mJ2Ab6VP9QArZ%2Fuploads%2FRzh03DsBHdDgjsqYvxP6%2Fimage.png?alt=media&#x26;token=cadb0387-dcdb-482c-8c5f-bcb84bd74b4b" alt=""><figcaption></figcaption></figure>

### Nerdctl&#x20;

If we wish to obtain low-level access and view the actual containers that have been executed in our cluster, we can achieve this by interacting with the Containerd service using the `nerdctl` command.\
i first show my all pods:&#x20;

```
kubectl get pod -o wide --all-namespaces
```

```
NAMESPACE              NAME                                         READY   STATUS    RESTARTS      AGE    IP              NODE   NOMINATED NODE   READINESS GATES
default                nginx-deployment-57d84f57dc-9cm5n            1/1     Running   0             36h    192.168.1.65    m2     <none>           <none>
default                nginx-deployment-57d84f57dc-vnhdl            1/1     Running   0             36h    192.168.1.4     m1     <none>           <none>
default                nginx-deployment-57d84f57dc-zbtnf            1/1     Running   0             36h    192.168.1.129   m3     <none>           <none>
kube-system            calico-kube-controllers-8787c9999-crv44      1/1     Running   0             37h    192.168.1.2     m1     <none>           <none>
kube-system            calico-node-bzrrn                            1/1     Running   0             37h    192.168.0.12    m2     <none>           <none>
kube-system            calico-node-cclqx                            1/1     Running   0             37h    192.168.0.13    m3     <none>           <none>
kube-system            calico-node-kmq4v                            1/1     Running   0             37h    192.168.0.11    m1     <none>           <none>
kube-system            coredns-5d78c9869d-h5fqx                     1/1     Running   0             39h    192.168.1.1     m1     <none>           <none>
kube-system            coredns-5d78c9869d-n2st9                     1/1     Running   0             39h    192.168.1.3     m1     <none>           <none>
kube-system            etcd-m1                                      1/1     Running   0             39h    192.168.0.11    m1     <none>           <none>
kube-system            etcd-m2                                      1/1     Running   0             37h    192.168.0.12    m2     <none>           <none>
kube-system            etcd-m3                                      1/1     Running   0             37h    192.168.0.13    m3     <none>           <none>
kube-system            kube-apiserver-m1                            1/1     Running   0             39h    192.168.0.11    m1     <none>           <none>
kube-system            kube-apiserver-m2                            1/1     Running   0             37h    192.168.0.12    m2     <none>           <none>
kube-system            kube-apiserver-m3                            1/1     Running   0             37h    192.168.0.13    m3     <none>           <none>
kube-system            kube-controller-manager-m1                   1/1     Running   2 (36h ago)   39h    192.168.0.11    m1     <none>           <none>
kube-system            kube-controller-manager-m2                   1/1     Running   0             37h    192.168.0.12    m2     <none>           <none>
kube-system            kube-controller-manager-m3                   1/1     Running   0             37h    192.168.0.13    m3     <none>           <none>
kube-system            kube-proxy-pnqbh                             1/1     Running   0             37h    192.168.0.12    m2     <none>           <none>
kube-system            kube-proxy-r5hgg                             1/1     Running   0             37h    192.168.0.13    m3     <none>           <none>
kube-system            kube-proxy-rpgzj                             1/1     Running   0             39h    192.168.0.11    m1     <none>           <none>
kube-system            kube-scheduler-m1                            1/1     Running   2 (36h ago)   39h    192.168.0.11    m1     <none>           <none>
kube-system            kube-scheduler-m2                            1/1     Running   0             37h    192.168.0.12    m2     <none>           <none>
kube-system            kube-scheduler-m3                            1/1     Running   0             37h    192.168.0.13    m3     <none>           <none>
kube-system            metrics-server-754586b847-5nq9g              1/1     Running   0             36h    192.168.0.13    m3     <none>           <none>
kubernetes-dashboard   dashboard-metrics-scraper-5cb4f4bb9c-phzk5   1/1     Running   0             167m   192.168.1.70    m2     <none>           <none>
kubernetes-dashboard   kubernetes-dashboard-6967859bff-v97cf        1/1     Running   0             167m   192.168.1.69    m2     <none>           <none>
```

now we need to install nerdctl binery command:&#x20;

Be notice this command should run in real cluster node worker or master

we are going to <https://github.com/containerd/nerdctl/releases> \
download the latest `nerdctl-X.X.X-linux-amd64.tar.gz`\
`tar Cxzvvf /usr/local/bin nerdctl-1.4.0-linux-amd64.tar.gz`

To list local Kubernetes containers:

```
nerdctl --namespace k8s.io ps
```

```
CONTAINER ID    IMAGE                                              COMMAND                   CREATED         STATUS    PORTS    NAMES
06f24761daf5    registry.k8s.io/coredns/coredns:v1.10.1            "/coredns -conf /etc…"    38 hours ago    Up                 k8s://kube-system/coredns-5d78c9869d-n2st9/coredns
16ebd8c74415    registry.k8s.io/pause:3.6                          "/pause"                  39 hours ago    Up                 k8s://kube-system/etcd-m1
1b432f7531f5    docker.io/calico/kube-controllers:master           "/usr/bin/kube-contr…"    38 hours ago    Up                 k8s://kube-system/calico-kube-controllers-8787c9999-crv44/calico-kube-controllers
23d8fec4511d    registry.k8s.io/kube-apiserver:v1.27.4             "kube-apiserver --ad…"    39 hours ago    Up                 k8s://kube-system/kube-apiserver-m1/kube-apiserver
275896c6dd7f    registry.k8s.io/coredns/coredns:v1.10.1            "/coredns -conf /etc…"    38 hours ago    Up                 k8s://kube-system/coredns-5d78c9869d-h5fqx/coredns
306c6dd14d8d    registry.k8s.io/pause:3.6                          "/pause"                  38 hours ago    Up                 k8s://kube-system/calico-node-kmq4v
3b65d7f057d3    registry.k8s.io/pause:3.6                          "/pause"                  38 hours ago    Up                 k8s://kube-system/coredns-5d78c9869d-n2st9
52cc18766427    registry.k8s.io/kube-controller-manager:v1.27.4    "kube-controller-man…"    37 hours ago    Up                 k8s://kube-system/kube-controller-manager-m1/kube-controller-manager
58b6b1ae7d74    registry.k8s.io/pause:3.6                          "/pause"                  38 hours ago    Up                 k8s://kube-system/coredns-5d78c9869d-h5fqx
60aa822e9b33    registry.k8s.io/pause:3.6                          "/pause"                  39 hours ago    Up                 k8s://kube-system/kube-scheduler-m1
63d13ff6c38d    registry.k8s.io/kube-proxy:v1.27.4                 "/usr/local/bin/kube…"    39 hours ago    Up                 k8s://kube-system/kube-proxy-rpgzj/kube-proxy
6b15bba0eb60    docker.io/calico/node:master                       "start_runit"             38 hours ago    Up                 k8s://kube-system/calico-node-kmq4v/calico-node
75590271afc2    registry.k8s.io/pause:3.6                          "/pause"                  38 hours ago    Up                 k8s://kube-system/calico-kube-controllers-8787c9999-crv44
96366b011c86    docker.io/library/nginx:latest                     "/docker-entrypoint.…"    36 hours ago    Up                 k8s://default/nginx-deployment-57d84f57dc-vnhdl/nginx
977097480a76    registry.k8s.io/pause:3.6                          "/pause"                  39 hours ago    Up                 k8s://kube-system/kube-proxy-rpgzj
9f57f821c543    registry.k8s.io/pause:3.6                          "/pause"                  36 hours ago    Up                 k8s://default/nginx-deployment-57d84f57dc-vnhdl
b38689662710    registry.k8s.io/kube-scheduler:v1.27.4             "kube-scheduler --au…"    37 hours ago    Up                 k8s://kube-system/kube-scheduler-m1/kube-scheduler
baafe67b6c2d    registry.k8s.io/pause:3.6                          "/pause"                  39 hours ago    Up                 k8s://kube-system/kube-apiserver-m1
dc1b4433c96f    registry.k8s.io/etcd:3.5.7-0                       "etcd --advertise-cl…"    39 hours ago    Up                 k8s://kube-system/etcd-m1/etcd
f67da4863037    registry.k8s.io/pause:3.6                          "/pause"                  39 hours ago    Up                 k8s://kube-system/kube-controller-manager-m1
```

For better productivity and ease of use, the command line syntax of `nerdctl` is designed to be similar to `Docker`.

### Install Helm 3 <a href="#install-helm-3-using-script" id="install-helm-3-using-script"></a>

#### Helm Prerequisites <a href="#helm-prerequisites" id="helm-prerequisites"></a>

You should have the following before getting started with the helm setup.

1. A running Kubernetes cluster.
2. The Kubernetes cluster API endpoint should be reachable from the machine you are running helm.
3. Authenticate the cluster using kubectl and it **should have cluster-admin permissions**.

Download the latest helm 3 installation script.

```
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
bash get_helm.sh
```

now we can verify `helm` is installed&#x20;

`helm version`

```
version.BuildInfo{Version:"v3.12.2", GitCommit:"1e210a2c8cc5117d1055bfaa5d40f51bbc2e345e", GitTreeState:"clean", GoVersion:"go1.20.5"}
```

```
helm search hub hello-world
```

```
URL                                                     CHART VERSION   APP VERSION     DESCRIPTION
https://artifacthub.io/packages/helm/hello-worl...      0.2.0           1.16.0          A Helm chart for Kubernetes
https://artifacthub.io/packages/helm/giantswarm...      2.0.0           0.2.0           A chart that deploys a basic hello world site a...
https://artifacthub.io/packages/helm/giantswarm...      1.3.5           0.2.0           A chart that deploys a basic hello world site a...
https://artifacthub.io/packages/helm/softonic/h...      1.2.2           0.2.0           A chart that deploys a basic hello world site a...
https://artifacthub.io/packages/helm/sikalabs/h...      0.6.0                           Hello World example chart
https://artifacthub.io/packages/helm/camptocamp...      1.0.1
https://artifacthub.io/packages/helm/lod/hello-...      0.1.0           1.16.0          A Helm chart for Kubernetes
```
