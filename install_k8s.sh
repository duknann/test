#!/bin/bash
set -e

echo "[1] Cập nhật hệ thống"
sudo apt update && sudo apt upgrade -y
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

echo "[2] Tắt swap"
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

echo "[3] Cài Docker"
sudo apt install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker

echo "[4] Cấu hình Docker dùng systemd cgroup"
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
sudo systemctl daemon-reexec && sudo systemctl restart docker

echo "[5] Kích hoạt module kernel và sysctl"
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system

echo "[6] Thêm repo Kubernetes (v1.30)"
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update

echo "[7] Cài kubeadm, kubelet, kubectl"
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

echo "[8] Cấu hình hostname (nên chỉnh thủ công nếu multi-node)"
sudo hostnamectl set-hostname master-node

echo "[9] Khởi tạo cluster với kubeadm"
sudo kubeadm init --control-plane-endpoint=master-node --upload-certs

echo "[10] Cấu hình kubeconfig cho user"
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "[11] Cài Flannel CNI"
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

echo "[12] Bỏ taint để chạy pod trên master node"
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

echo "✅ Hoàn tất cài đặt Master Node. Bạn có thể copy kubeadm join để thêm worker."