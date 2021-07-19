#!/bin/bash

echo ""
echo "Example Docker Desktop with Kubernetes option checked - install"
echo ""
echo ""
echo "Includes Dev URLs setup on localhost"
echo ""
echo ""

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

kubectl config use-context docker-desktop
kubectl create namespace coder
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
    --set ingress.host="local.coder" \
    --set devurls.host="*.dev.coder" \
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
  --timeout=1m

echo ""
echo "Waiting for services ( cemanager and envproxy ) to be ready..."

kubectl wait  \
  --for=condition=ready pod \
  --selector=coder.deployment=cemanager \
  --timeout=1m
kubectl wait  \
  --for=condition=ready pod \
  --selector=coder.deployment=envproxy \
  --timeout=1m

echo ""
kubectl get all -n coder


echo ""
echo ""
echo "OPTIONAL STEPS TO GET DEV URLS WORKING:"
echo ""
echo "1. brew install dnsmasq and add an entries for the ingress and devurl hosts on /usr/local/etc/dnsmasq.conf:"
echo ""
echo "address=/.dev.coder/127.0.0.1"
echo "address=/.local.coder/127.0.0.1"
echo ""
echo ""
echo "start dnsmasq with:"
echo "brew services dnsmasq start"
echo ""
echo ""
echo "If you change dnsmasq settings, you need to restart it:"
echo "brew services dnsmasq restart"
echo ""
echo ""
echo "2. go into your Mac settings->network->advanced->dns and put 127.0.0.1 as first nameserver before your local router and Internet e.g., 192.168.1.1 and 8.8.8.8"
echo ""
echo ""
echo "You can now access Coder at"
echo ""
echo "    http://local.coder"
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
echo "    within the Docker Desktop UI config (wrench icon), reset or disable Kubernetes "
echo ""
echo ""
echo ""

echo "Platform credentials"
kubectl logs \
  -l coder.deployment=cemanager \
  -c cemanager \
  --tail=80 \
  --follow=false | \
  grep -E '(User|Password)'
