#!/bin/bash

set -e

USERNAME=${SUDO_USER}
NAMESPACE=$USERNAME

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

dpkg -l kubelet >/dev/null 2>&1 || (
  log_start "Installing kubernetes.."
  [ -d /etc/apt/sources.list.d/kubernetes.list ] \
    || cat <<EOF > /etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
  apt-get update && apt-get install -y docker.io kubelet kubeadm kubectl kubernetes-cni
  chmod o+rw /run/docker.sock
  mkdir -p /etc/systemd/system/docker.socket.d/
  cat << EOF > /etc/systemd/system/docker.socket.d/override.conf
[Socket]
SocketMode=0666
EOF
  log_end
)

[ -d /etc/kubernetes/pki ] || (
  log_start "Initializing Cluster.."
  kubeadm init && sleep 2
  kubectl taint nodes --all dedicated-
  chmod 644 /etc/kubernetes/admin.conf
  log_end
)

kubectl describe daemonset weave-net --namespace=kube-system > /dev/null 2>&1 || (
  log_start "Setting up pod network.."
  kubectl apply -f https://git.io/weave-kube
  log_end
)

kubectl describe deployment kubernetes-dashboard --namespace=kube-system >/dev/null 2>&1 || (
  log_start "Setting up dashboard.."
  kubectl apply -f https://rawgit.com/kubernetes/dashboard/master/src/deploy/kubernetes-dashboard.yaml
  log_end
)

log_start "Configuring basic-auth for api server.."
[ -e /etc/kubernetes/pki/basic-auth.csv ] \
  || echo 'admin,admin,1000' > /etc/kubernetes/pki/basic-auth.csv
grep 'basic-auth-file' /etc/kubernetes/manifests/kube-apiserver.json >/dev/null || (
  sed -i -e 's;"--token-auth-file=/etc/kubernetes/pki/tokens.csv",;"--token-auth-file=/etc/kubernetes/pki/tokens.csv",\n          "--basic-auth-file=/etc/kubernetes/pki/basic-auth.csv",;' /etc/kubernetes/manifests/kube-apiserver.json
  kill -HUP $(pidof kube-apiserver)
  echo "waiting 20s for kube-apiserver to restart"
  sleep 20
)
log_end

log_start "Waiting for cluster pods to become ready.."
while kubectl get pods --all-namespaces | awk '{print $4}' | grep -v STATUS | grep -v Running > /dev/null; do
  echo -n "."
  sleep 3
done
echo
echo "Pods ready, waiting another 10s"
sleep 10
log_end

[ -d ~/.kube ] && sudo chown -R $USERNAME:$USERNAME ~/.kube

kubectl describe rc kube-registry-v0 --namespace=kube-system >/dev/null 2>&1 || (
  log_start "Setting up kubernetes registry.."
  mkdir -p /tmp/kube-registry
  [ -e /tmp/kube-registry/registry.key ] || (
    cd /tmp/kube-registry
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
CN                     = kube-registry.kube-system.svc.cluster.local
emailAddress           = test@email.address
EOF
    openssl req -x509 -config openssl-config -nodes -newkey rsa:2048 -keyout registry.key -out registry.crt > /dev/null
  )
  kubectl --namespace=kube-system describe secret registry-tls-secret > /dev/null || (
    cd /tmp/kube-registry
    kubectl --namespace=kube-system create secret generic registry-tls-secret --from-file=registry.crt=registry.crt --from-file=registry.key=registry.key
  )
  mkdir -p /data/kube-registry
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ReplicationController
metadata:
  name: kube-registry-v0
  namespace: kube-system
  labels:
    k8s-app: kube-registry
    version: v0
spec:
  replicas: 1
  selector:
    k8s-app: kube-registry
    version: v0
  template:
    metadata:
      labels:
        k8s-app: kube-registry
        version: v0
    spec:
      containers:
      - name: registry
        image: registry:2
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
          path: /data/kube-registry
      - name: cert-dir
        secret:
          secretName: registry-tls-secret
---
apiVersion: v1
kind: Service
metadata:
  name: kube-registry
  namespace: kube-system
  labels:
    k8s-app: kube-registry
    kubernetes.io/name: "KubeRegistry"
spec:
  selector:
    k8s-app: kube-registry
  ports:
  - name: registry
    port: 5000
    protocol: TCP

EOF
  cp /tmp/kube-registry/registry.crt /etc/docker/certs.d/kube-registry.kube-system.svc.cluster.local\:5000/ca.crt
  log_end
)

log_start "Configuring name resolution.."
#apt-get install dnsmasq
#cat << EOF >/etc/dnsmasq.d/10-kubernetes-cluster.conf
#server=/cluster.local/100.64.0.10
#EOF
#sed -i -e 's;^#conf-dir=/etc/dnsmasq\.d/,\*\.conf;conf-dir=/etc/dnsmasq.d/,*.conf;' /etc/dnsmasq.conf
#service dnsmasq restart
sed -i -e 's;iface eth0 inet dhcp;iface eth0 inet dhcp\ndns-nameserver 100.64.0.10;' /etc/network/interfaces
ifdown eth0
ifup eth0
log_end

log_start "Pulling and pushing images.."
for img in ws-jenkins:1.1 ruby-phonebook:019ab7bab4cc ; do
  docker pull pingworks/$img
  docker tag pingworks/$img kube-registry.kube-system.svc.cluster.local:5000/$img
  docker push kube-registry.kube-system.svc.cluster.local:5000/$img
done
log_end

log_start "Creating namespaces.."
for ns in $NAMESPACE prod; do
  kubectl get namespace $ns >/dev/null || kubectl create namespace $ns
done
log_end

log_start "Deploying Jenkins pod and service.."
mkdir -p /data/jenkins/{workspace,jobs/backend,jobs/frontend}
cat << EOF >/data/jenkins/jobs/backend/config.xml
<?xml version='1.0' encoding='UTF-8'?>
<flow-definition plugin="workflow-job@2.7">
  <actions/>
  <description></description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <com.dabsquared.gitlabjenkins.connection.GitLabConnectionProperty plugin="gitlab-plugin@1.4.2">
      <gitLabConnection>gitlab</gitLabConnection>
    </com.dabsquared.gitlabjenkins.connection.GitLabConnectionProperty>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.StringParameterDefinition>
          <name>VERSION</name>
          <description></description>
          <defaultValue></defaultValue>
        </hudson.model.StringParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
    <org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>
      <triggers/>
    </org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps@2.18">
    <script>node {
    stage(&apos;CS:Preparation&apos;) {
        checkout([\$class: &apos;GitSCM&apos;, branches: [[name: &apos;\$VERSION&apos;]], extensions: [[\$class: &apos;RelativeTargetDirectory&apos;, relativeTargetDir: &apos;backend&apos;]], userRemoteConfigs: [[url: &apos;https://github.com/pingworks/phonebook-backend.git&apos;]]])
        checkout([\$class: &apos;GitSCM&apos;, extensions: [[\$class: &apos;RelativeTargetDirectory&apos;, relativeTargetDir: &apos;buildscripts&apos;]], userRemoteConfigs: [[url: &apos;https://github.com/pingworks/phonebook-buildscripts.git&apos;]]])
    }
    stage(&apos;CS:Build &amp; Test&apos;) {
        sh &apos;buildscripts/kubernetes-run.sh phonebook-build-backend ruby-phonebook:019ab7bab4cc &quot;/src/\${JOB_NAME}/buildscripts/build-and-test.sh backend 1git\${VERSION}&quot;&apos;
        sh &apos;\${KUBECTL} delete pod --namespace=&quot;\$NAMESPACE&quot; phonebook-build-backend&apos;
    }
    stage(&apos;CS:Results&apos;) {
        //junit &apos;backend/rspec*.xml&apos;
        archive &quot;backend/*.deb&quot;
    }
    stage(&apos;CS:Application Image&apos;) {
        withEnv([&quot;ARTEFACT_FILE=phonebook-backend_1git\${VERSION}_amd64.deb&quot;,&quot;TAG=kube-registry.kube-system.svc.cluster.local:5000/phonebook-backend:1git\${VERSION}&quot;]) {
            sh &apos;docker build --build-arg ARTEFACT_FILE=&quot;\$ARTEFACT_FILE&quot; -t \$TAG backend&apos;
            sh &apos;docker push \$TAG&apos;
        }
    }
    stage(&apos;ATS:Preparation&apos;) {
        sh &apos;buildscripts/deploy-phonebook.sh backend \$VERSION&apos;
        sh &apos;buildscripts/wait-for-pod-state.sh app=phonebook-backend,stage=pipeline Running 30&apos;
    }
    stage(&apos;ATS:Test&apos;) {
        sh &apos;buildscripts/kubernetes-run.sh phonebook-test-backend ruby-phonebook:019ab7bab4cc &quot;/src/\${JOB_NAME}/buildscripts/inttest.sh /src/\${JOB_NAME}/backend&quot;&apos;
        junit &apos;backend/rspec*.xml&apos;
    }
    stage(&apos;ATS:Cleanup&apos;) {
        sh &apos;\${KUBECTL} delete pod --namespace=&quot;\$NAMESPACE&quot; phonebook-test-backend&apos;
        sh &apos;buildscripts/undeploy-phonebook.sh backend \$VERSION&apos;
    }
}</script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <authToken>a12fde257cad123929237</authToken>
</flow-definition>
EOF
cat << EOF > /data/jenkins/jobs/frontend/config.xml
<?xml version='1.0' encoding='UTF-8'?>
<flow-definition plugin="workflow-job@2.7">
  <actions/>
  <description></description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <com.dabsquared.gitlabjenkins.connection.GitLabConnectionProperty plugin="gitlab-plugin@1.4.2">
      <gitLabConnection>gitlab</gitLabConnection>
    </com.dabsquared.gitlabjenkins.connection.GitLabConnectionProperty>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.StringParameterDefinition>
          <name>VERSION</name>
          <description></description>
          <defaultValue></defaultValue>
        </hudson.model.StringParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
    <org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>
      <triggers/>
    </org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps@2.18">
    <script>node {
    stage(&apos;CS:Preparation&apos;) {
        checkout([\$class: &apos;GitSCM&apos;, branches: [[name: &apos;\$VERSION&apos;]], extensions: [[\$class: &apos;RelativeTargetDirectory&apos;, relativeTargetDir: &apos;frontend&apos;]], userRemoteConfigs: [[url: &apos;https://github.com/pingworks/phonebook-frontend.git&apos;]]])
        checkout([\$class: &apos;GitSCM&apos;, extensions: [[\$class: &apos;RelativeTargetDirectory&apos;, relativeTargetDir: &apos;buildscripts&apos;]], userRemoteConfigs: [[url: &apos;https://github.com/pingworks/phonebook-buildscripts.git&apos;]]])
   }
    stage(&apos;CS:Build &amp; Test&apos;) {
        sh &apos;buildscripts/kubernetes-run.sh phonebook-build-frontend ruby-phonebook:019ab7bab4cc &quot;/src/\${JOB_NAME}/buildscripts/build-and-test.sh frontend 1git\${VERSION}&quot;&apos;
        sh &apos;\${KUBECTL} delete pod --namespace=&quot;\$NAMESPACE&quot; phonebook-build-frontend&apos;
    }
    stage(&apos;CS:Results&apos;) {
        //junit &apos;frontend/rspec*.xml&apos;
        archive &quot;frontend/*.deb&quot;
    }
    stage(&apos;CS:Application Image&apos;) {
        withEnv([&quot;ARTEFACT_FILE=phonebook-frontend_1git\${VERSION}_amd64.deb&quot;,&quot;TAG=kube-registry.kube-system.svc.cluster.local:5000/phonebook-frontend:1git\${VERSION}&quot;]) {
            sh &apos;docker build --build-arg ARTEFACT_FILE=&quot;\$ARTEFACT_FILE&quot; -t \$TAG frontend&apos;
            sh &apos;docker push \$TAG&apos;
        }
    }
    stage(&apos;ATS:Preparation&apos;) {
        sh &apos;buildscripts/deploy-phonebook.sh frontend \$VERSION&apos;
        sh &apos;buildscripts/wait-for-pod-state.sh app=phonebook-frontend,stage=pipeline Running 30&apos;
    }
    stage(&apos;ATS:Test&apos;) {
        retry(3) {
            sh &apos;sleep 3 &amp;&amp; curl http://phonebook-frontend/ | grep &quot;&lt;title&gt;Phonebook&lt;/title&gt;&quot;&apos;
        }
    }
    stage(&apos;ATS:Cleanup&apos;) {
        sh &apos;buildscripts/undeploy-phonebook.sh frontend \$VERSION&apos;
    }
}</script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <authToken>a12fde257cad123929237</authToken>
</flow-definition>
EOF

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
        image: kube-registry.kube-system.svc.cluster.local:5000/ws-jenkins:1.1
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