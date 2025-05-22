#!/bin/bash
# install-k8s-with-audit.sh - Install Kubernetes 1.30 with audit logging (Ubuntu 22.04+)

set -e

echo "[1/8] Update and install dependencies..."
apt-get update && apt-get install -y apt-transport-https ca-certificates curl gpg sudo

echo "[2/8] Add Kubernetes APT repo..."
curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" > /etc/apt/sources.list.d/kubernetes.list

echo "[3/8] Install kubeadm, kubelet, kubectl..."
apt-get update && apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

echo "[4/8] Disable swap..."
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

echo "[5/8] Enable containerd..."
systemctl enable --now containerd

echo "[6/8] Create audit-policy.yaml..."
mkdir -p /etc/kubernetes
cat <<EOF > /etc/kubernetes/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: Metadata
    resources:
    - group: ""
      resources: ["pods", "secrets", "configmaps"]
  - level: RequestResponse
    verbs: ["create", "delete", "patch", "update"]
    resources:
    - group: "authentication.k8s.io"
      resources: ["tokenreviews"]
EOF

echo "[7/8] Create kubeadm-config.yaml..."
cat <<EOF > /root/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "$(hostname -I | awk '{print $1}')"
  bindPort: 6443
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: "v1.30.1"
apiServer:
  extraArgs:
    audit-log-path: "/var/log/kubernetes/audit.log"
    audit-policy-file: "/etc/kubernetes/audit-policy.yaml"
  extraVolumes:
    - name: auditlog
      hostPath: /var/log/kubernetes
      mountPath: /var/log/kubernetes
      pathType: DirectoryOrCreate
      readOnly: false
    - name: auditpolicy
      hostPath: /etc/kubernetes/audit-policy.yaml
      mountPath: /etc/kubernetes/audit-policy.yaml
      pathType: File
      readOnly: true
EOF

echo "[8/8] Init Kubernetes cluster..."
mkdir -p /var/log/kubernetes
kubeadm init --config=/root/kubeadm-config.yaml

echo "✅ Done! Now run the following to start using your cluster:"
echo "  mkdir -p \$HOME/.kube"
echo "  cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config"
echo "  chown \$(id -u):\$(id -g) \$HOME/.kube/config"
