#!/bin/bash

set -euo pipefail

if ! command -v kubectl &> /dev/null
then
  echo "Please install kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl"
  exit
fi

if ! command -v helm &> /dev/null
then
  echo "Please install helm: https://helm.sh/docs/intro/install"
  exit
fi

echo ""
echo "Installation of Coder's developer workspace platform on a single-node cluster..."
echo ""
echo "assumes Kubernetes has been enabled from within Docker Desktop..."
echo ""
echo "will install an Nginx ingress controller as a pod in the coder namespace..."
echo ""
echo ""
echo ""
echo "Creating and switching to the coder namespace and setting context..."

kubectl create namespace coder
kubectl config use-context docker-desktop
kubectl config set-context --current --namespace=coder

echo ""
echo "adding and updating coder and bitnami ( for metrics server ) helm repos..."

helm repo add coder https://helm.coder.com
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm install metrics-server \
--set apiService.create="true" \
--set command="{metrics-server,--kubelet-insecure-tls,--kubelet-preferred-address-types=InternalIP}" \
--version 5.8.6 \
bitnami/metrics-server

echo ""
echo "Installing latest version of coder..."
echo "using built-in nginx ingress that coder provides..."
echo ""

helm repo add coder https://helm.coder.com
helm repo update
helm install coder \
    --set cemanager.resources.requests.cpu="0m" \
    --set cemanager.resources.requests.memory="0Mi" \
    --set envproxy.resources.requests.cpu="0m" \
    --set envproxy.resources.requests.memory="0Mi" \
    --set dashboard.resources.requests.cpu="0m" \
    --set dashboard.resources.requests.memory="0Mi" \
    --set timescale.resources.requests.cpu="0m" \
    --set timescale.resources.requests.memory="0Mi" \
    coder/coder

echo ""
echo "Waiting for postgres database to be ready..."

kubectl wait  \
  --for=condition=ready pod \
  --selector=app=timescale \
  --timeout=3m

echo ""
echo "Waiting for services ( cemanager and envproxy ) to be ready..."

kubectl wait  \
  --for=condition=ready pod \
  --selector=coder.deployment=cemanager \
  --timeout=3m
kubectl wait  \
  --for=condition=ready pod \
  --selector=coder.deployment=envproxy \
  --timeout=3m

echo ""
kubectl get all -n coder

echo ""
echo "You can now access Coder at"
echo ""
echo "    http://localhost"
echo ""
echo "You can tear down the deployment with either:"
echo ""
echo "    kubectl delete namespaces coder "
echo ""
echo "or"
echo ""
echo "    helm uninstall coder --namespace coder "
echo ""
echo "or"
echo ""
echo "    within the Docker Desktop config (wrench), reset or disable Kubernetes "
echo ""

echo ""
echo "You should consider helm upgrading with ingress.host and devurls.host to enable Dev URLs"
echo ""

echo "Platform credentials"
kubectl logs \
  -l coder.deployment=cemanager \
  -c cemanager \
  --tail=80 \
  --follow=false | \
  grep -E '(User|Password)'
