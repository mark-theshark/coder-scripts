#!/bin/bash

echo ""
echo "Janky k3d install script by Mark Milligan, hacked from bits of one in m repo and other bits."
echo ""
echo ""
echo "Includes Dev URLs setup with custom local domains"
echo ""
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
echo "port 80 from the localhost will be mapped to port 80 on the load balancer container"
echo ""

k3d cluster create local-coder \
  --api-port 6550 \
  -p "80:80@loadbalancer" \
  -p "5349:5349@loadbalancer"

echo ""
echo "Creating and switching to the coder namespace and setting context..."

kubectl create namespace coder
kubectl config use-context k3d-local-coder
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
    --set ingress.host="coder.k3d.local" \
    --set devurls.host="*.dev.k3d.local" \
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
echo "using networking.k8s.io/v1"

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress
spec:
  rules:
  - host: "coder.k3d.local"
    http:
      paths:
      - pathType: Prefix
        path: "/proxy/"
        backend:
          service:
            name: envproxy
            port:
              number: 8080
      - pathType: Prefix
        path: "/api/"
        backend:
          service:
            name: cemanager
            port:
              number: 8080
      - pathType: Prefix
        path: "/auth/"
        backend:
          service:
            name: cemanager
            port:
              number: 8080
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: dashboard
            port:
              number: 3000              
  - host: "*.dev.k3d.local"
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: envproxy
            port:
              number: 8080
EOF

echo ""
echo "Waiting for postgres timescale database to be ready..."

kubectl wait  \
  --for=condition=ready pod \
  --selector=app=timescale \
  --timeout=3m

echo ""
echo "Waiting for services ( ce manager and envproxy ) to be ready..."

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
echo ""
echo "OPTIONAL STEPS TO GET DEV URLS WORKING:"
echo ""
echo "1. brew install dnsmasq and add an entries for the ingress and devurl hosts on /usr/local/etc/dnsmasq.conf:"
echo ""
echo "address=/.dev.k3d.local/127.0.0.1"
echo "address=/.coder.k3d.local/127.0.0.1"
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
echo "You can now access coder at"
echo ""
echo "    http://coder.k3d.local"
echo ""
echo "You can tear down the deployment with"
echo ""
echo "    k3d cluster delete coder"
echo ""
echo "When in doubt, reboot your mac if any dns or dev URL things are not working."
echo ""
echo "You can see"
echo ""

echo "coder platform credentials"
kubectl logs \
  -l coder.deployment=cemanager \
  -c cemanager \
  --tail=80 \
  --follow=false | \
  grep -E '(User|Password)'
