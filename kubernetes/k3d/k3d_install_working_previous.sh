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

if ! command -v k3d &> /dev/null
then
  echo "Please install k3d: https://k3d.io/#installation"
  exit
fi

echo ""
echo "Creating a single-node cluster with k3d including..."
echo ""
echo "1 container running k3s..."
echo "1 container running a load balancer..."
echo "a traefik ingress controller..."
echo ""
echo "port 8081 from the localhost will be mapped to port 80 on the load balancer container"
echo ""

k3d cluster create coder \
  --api-port 6550 \
  -p "8081:80@loadbalancer"

echo ""
echo "Creating and switching to the coder namespace and setting context..."

kubectl create namespace coder
kubectl config use-context k3d-coder
kubectl config set-context --current --namespace=coder

echo ""
echo "Waiting for traefik ingress to be ready..."

n=0
until [ "$n" -ge 10 ]
do
  kubectl wait --namespace kube-system \
    --for=condition=ready pod \
    --selector=app=traefik \
    --timeout=90s \
    2>/dev/null \
    && break
  n=$((n+1)) 
  sleep 5
done

echo ""
echo "Installing latest version of Coder..."
echo "and not using built-in nginx ingress that coder provides..."
echo ""

helm repo add coder https://helm.coder.com
helm repo update
helm install coder \
    --set ingress.useDefault=false \
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
echo "manually setting up ingress routes..."

cat <<EOF | kubectl apply -f -
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: web-ingress
  namespace: "coder"
spec:
  rules:
  - http:
      paths:
      - path: /proxy/
        backend:
          serviceName: envproxy
          servicePort: 8080
      - path: /api/
        backend:
          serviceName: cemanager
          servicePort: 8080
      - path: /auth/
        backend:
          serviceName: cemanager
          servicePort: 8080
      - path: /
        backend:
          serviceName: dashboard
          servicePort: 3000
EOF

echo ""
echo "Waiting for postgres to be ready..."

kubectl wait  \
  --for=condition=ready pod \
  --selector=app=timescale \
  --timeout=3m

echo ""
echo "Waiting for services to be ready..."

kubectl wait  \
  --for=condition=ready pod \
  --selector=coder.deployment=cemanager \
  --timeout=3m
kubectl wait  \
  --for=condition=ready pod \
  --selector=coder.deployment=envproxy \
  --timeout=3m

echo ""
kubectl get pods


echo ""
echo "You can now access Coder at"
echo ""
echo "    http://localhost:8081"
echo ""
echo "You can tear down the deployment with"
echo ""
echo "    k3d cluster delete coder"
echo ""

echo "Platform credentials"
kubectl logs \
  -l coder.deployment=cemanager \
  -c cemanager \
  --tail=80 \
  --follow=false | \
  grep -E '(User|Password)'
