#!/bin/bash

set -e

KUBEVERSION="v1.6.2"
SVCCIDR="10.96.0.0/12"
SVCDOMAIN="cluster.local"
CLUSTERDNS="10.96.0.10"
APISERVER="10.96.0.1"
SEARCHDOMAIN="infra.svc.cluster.local kube-system.svc.cluster.local"

USERNAME=${SUDO_USER}
NAMESPACE=$USERNAME

PBFE="86520c3"
PBBE="5adb548"

function log_start {
  echo "####################################"
  echo "# $1"
  echo "####################################"
}

function log_end {
  echo "####################################"
  echo "# done."
  echo "####################################"
  echo
}

[ -d ~/.kube.workshop ] || (
  log_start "Moving old kubeconfig"
  [ -d ~/.kube ] && mv ~/.kube ~/.kube.workshop
  log_end
)

id $USERNAME | grep docker > /dev/null || (
  log_start "Adding user to docker group.."
  adduser $USERNAME docker
  log_end
)

log_start "Installing kubernetes.."
dpkg -l kubelet >/dev/null 2>&1 || (
  dpkg -l apt-transport-https > /dev/null 2>&1 || apt-get update && apt-get install -y apt-transport-https
  apt-key list | grep 2048R/A7317B0F >/dev/null || curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  [ -e /etc/apt/sources.list.d/kubernetes.list ] || (
    echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' >/etc/apt/sources.list.d/kubernetes.list
    apt-get update
  )
  dpkg -l docker-engine > /dev/null 2>&1 || apt-get install -y docker-engine
  dpkg -l kubelet > /dev/null 2>&1 || apt-get install -y kubelet kubeadm kubectl kubernetes-cni

  [ -d /etc/kubernetes/pki ] || (
    grep 'cluster-dns=${CLUSTERDNS}' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf >/dev/null || (
      sed -i -e "s;--cluster-dns=[0-9\.]* ;--cluster-dns=${CLUSTERDNS} ;" \
          -e "s;--cluster-domain=cluster.local;--cluster-domain=${SVCDOMAIN};" \
          /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
      systemctl daemon-reload
      systemctl restart kubelet
      sleep 10
    )
  )
)
log_end

log_start "Setting up docker installation.."
[ -e /etc/systemd/system/docker.socket.d/override.conf ] || (
  chmod o+rw /run/docker.sock
  mkdir -p /etc/systemd/system/docker.socket.d/
  cat << EOF > /etc/systemd/system/docker.socket.d/override.conf
[Socket]
SocketMode=0666
EOF
)
[ -e /etc/systemd/system/docker.service.d/override.conf ] || (
  mkdir -p /etc/systemd/system/docker.service.d/
  cat << EOF >/etc/systemd/system/docker.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H fd:// -H localhost \$DOCKER_OPTS
EOF
  systemctl daemon-reload
  systemctl restart docker
)

log_start "Initializing cluster.."
[ -d /etc/kubernetes/pki ] || (
  kubeadm init \
    --skip-preflight-checks \
    --kubernetes-version ${KUBEVERSION} \
    --service-cidr ${SVCCIDR} \
    --service-dns-domain ${SVCDOMAIN} \
    | tee kubeinit.out && sleep 2
  mkdir -p ${HOME}/.kube
  cp -a /etc/kubernetes/admin.conf ${HOME}/.kube/config
  kubectl taint nodes --all node-role.kubernetes.io/master-
)

kubectl describe daemonset weave-net --namespace=kube-system > /dev/null 2>&1 || (
  log_start "Setting up pod network.."
  curl -L https://git.io/weave-kube-1.6 > weave-kube-1.6.yaml
  sed -i -e 's;name: weave$;name: weave\n          env:\n            - name: IPALLOC_RANGE\n              value: 10.48.0.0/16;' weave-kube-1.6.yaml
  kubectl apply -f weave-kube-1.6.yaml
  log_end
)

kubectl get deployment kubernetes-dashboard --namespace=kube-system >/dev/null 2>&1 || (
  log_start "Setting up dashboard.."
  kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/kubernetes-dashboard.yaml
  log_end
)

log_start "Waiting for cluster pods to become ready.."
output=$(kubectl get pods --all-namespaces)
echo "$output"
while echo "$output" | awk '{print $4}' | grep -v STATUS | grep -v Running >/dev/null; do
  echo '------------------- Waiting 3 sec. -------------------'
  sleep 3
  output=$(kubectl get pods --all-namespaces)
  echo "$output"
done
echo
echo "Pods ready, waiting another 10s"
sleep 10
log_end

[ -d ~/.kube ] && sudo chown -R $USERNAME:$USERNAME ~/.kube

log_start "Creating namespaces.."
for ns in $NAMESPACE infra prod; do
  kubectl get namespace $ns >/dev/null || kubectl create namespace $ns
done
kubectl get rolebinding sa-default-edit --namespace=$USERNAME || kubectl create rolebinding sa-default-edit --clusterrole=edit --serviceaccount=$USERNAME:default --namespace=$USERNAME
log_end

kubectl describe rc registry --namespace=infra >/dev/null 2>&1 || (
  log_start "Setting up kubernetes registry.."
  mkdir -p /tmp/registry
  [ -e /tmp/registry/registry.key ] || (
    cd /tmp/registry
    cat << EOF >openssl-config
[ req ]
default_bits           = 2048
distinguished_name     = req_distinguished_name
prompt                 = no

[ req_distinguished_name ]
C                      = DE
ST                     = Kubernetes
L                      = Kubernetes
O                      = Kubernetes
OU                     = pingworks
CN                     = registry
emailAddress           = test@email.address
EOF
    openssl req -x509 -config openssl-config -days 1825 -nodes -newkey rsa:2048 -keyout registry.key -out registry.crt > /dev/null
  )
  kubectl --namespace=infra describe secret registry-tls-secret > /dev/null || (
    cd /tmp/registry
    kubectl --namespace=infra create secret generic registry-tls-secret --from-file=registry.crt=registry.crt --from-file=registry.key=registry.key
  )
  mkdir -p /data/registry
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ReplicationController
metadata:
  name: registry
  namespace: infra
  labels:
    k8s-app: registry
spec:
  replicas: 1
  selector:
    k8s-app: registry
  template:
    metadata:
      labels:
        k8s-app: registry
    spec:
      containers:
      - name: registry
        image: registry:2.6.1
        env:
        - name: REGISTRY_HTTP_ADDR
          value: :5000
        - name: REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY
          value: /var/lib/registry
        - name: REGISTRY_HTTP_TLS_CERTIFICATE
          value: /certs/registry.crt
        - name: REGISTRY_HTTP_TLS_KEY
          value: /certs/registry.key
        volumeMounts:
        - name: image-store
          mountPath: /var/lib/registry
        - name: cert-dir
          mountPath: /certs
        ports:
        - containerPort: 5000
          name: registry
          protocol: TCP
      volumes:
      - name: image-store
        hostPath:
          path: /data/registry
      - name: cert-dir
        secret:
          secretName: registry-tls-secret
---
apiVersion: v1
kind: Service
metadata:
  name: registry
  namespace: infra
  labels:
    k8s-app: registry
    kubernetes.io/name: "Registry"
spec:
  selector:
    k8s-app: registry
  ports:
  - name: registry
    port: 5000
    protocol: TCP

EOF
  mkdir -p /etc/docker/certs.d/registry\:5000
  cp /tmp/registry/registry.crt /etc/docker/certs.d/registry\:5000/ca.crt
  log_end
)

log_start "Configuring name resolution.."
grep "nameserver ${CLUSTERDNS}" /etc/resolvconf/resolv.conf.d/head || (
  echo "search ${NAMESPACE}.svc.cluster.local infra.svc.cluster.local kube-system.svc.cluster.local" >> /etc/resolvconf/resolv.conf.d/head
  echo "nameserver ${CLUSTERDNS}" >> /etc/resolvconf/resolv.conf.d/head
  echo "nameserver 8.8.8.8" >> /etc/resolvconf/resolv.conf.d/head
  systemctl restart networking
)
log_end

log_start "Pulling and pushing images.."
for img in pingworks/ws-docker:1.11.2-1 pingworks/ws-kubectl:1.6.2-2 pingworks/ruby-phonebook:019ab7bab4cc library/nginx:1.13.0; do
  docker pull $img
  docker tag $img registry:5000/infra/${img#*/}
  docker push registry:5000/infra/${img#*/}
done
log_end

log_start "Deploying Jenkins pod and service.."
mkdir -p /data/jenkins/{workspace,jobs/backend-pipeline,jobs/frontend-pipeline,jobs/backend,jobs/frontend}
chmod 777 /data/jenkins/workspace
ln -s /data/jenkins /var/jenkins_home
cp resources/backend-pipeline.xml /data/jenkins/jobs/backend-pipeline/config.xml
cp resources/frontend-pipeline.xml /data/jenkins/jobs/frontend-pipeline/config.xml

chown -R 1000:1000 /data/jenkins

cat << EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-$USERNAME-jenkins-workspace
  namespace: $NAMESPACE
  labels:
    app: jenkins
    container: jenkins
    dir: workspace
spec:
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /data/jenkins/workspace
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: pvc-$USERNAME-jenkins-workspace
  namespace: $NAMESPACE
  labels:
    app: jenkins
    container: jenkins
    dir: workspace
spec:
  accessModes:
    - ReadWriteOnce
  selector:
    matchLabels:
      app: jenkins
      container: jenkins
      dir: workspace
  resources:
    requests:
      storage: 2Gi
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: jenkins
  namespace: $NAMESPACE
  labels:
    app: jenkins
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: jenkins
    spec:
      containers:
      - name: jenkins
        image: pingworks/ws-jenkins:1.5.4-local
        volumeMounts:
        - name: jenkins-workspace
          mountPath: /var/jenkins_home/workspace
        - name: jenkins-jobs
          mountPath: /var/jenkins_home/jobs
        - name: jenkins-docker-socket
          mountPath: /run/docker.sock
        ports:
        - containerPort: 50000
        - containerPort: 8080
        env:
        - name: JAVA_OPTS
          value: -Djenkins.install.runSetupWizard=false
        - name: NAMESPACE
          value: "$NAMESPACE"
        - name: FQDN
          value: "jenkins.$NAMESPACE.svc.cluster.local"
      volumes:
      - name: jenkins-workspace
        persistentVolumeClaim:
          claimName: pvc-$USERNAME-jenkins-workspace
      - name: jenkins-jobs
        hostPath:
          path: "/data/jenkins/jobs"
      - name: jenkins-docker-socket
        hostPath:
          path: "/run/docker.sock"
---
apiVersion: v1
kind: Service
metadata:
  name: jenkins
  namespace: $NAMESPACE
  labels:
    app: jenkins
spec:
  selector:
    app: jenkins
  ports:
  - name: jenkins50000
    port: 50000
    protocol: TCP
  - name: jenkins8080
    port: 80
    targetPort: 8080
    protocol: TCP
EOF
log_end

echo "########################################################################"
echo "# Your local cluster is setup."
echo "# You can access the kubernetes dashboard at: https://kubernetes.default.svc.cluster.local/ui"
echo "# Your jenkins is available at: http://jenkins.$NAMESPACE.svc.cluster.local"
echo "########################################################################"
echo
