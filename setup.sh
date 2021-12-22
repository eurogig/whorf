#!/usr/bin/env bash
# setup.sh
#
# Sets up the files required to deploy the Bridgecrew Checkov admission controller in a cluster

set -euo pipefail

mkdir bridgecrew
k8sdir="$(dirname "$0")/bridgecrew"
certdir="$(mktemp -d)"

# Get the files we need
namespace=https://raw.githubusercontent.com/eurogig/whorf/main/k8s/namespace.yaml
deployment=https://raw.githubusercontent.com/eurogig/whorf/main/k8s/deployment.yaml
configmap=https://raw.githubusercontent.com/eurogig/whorf/main/k8s/checkovconfig.yaml
admissionregistration=https://raw.githubusercontent.com/eurogig/whorf/main/k8s/admissionconfiguration.yaml
service=https://raw.githubusercontent.com/eurogig/whorf/main/k8s/service.yaml

curl -o $k8sdir/namespace.yaml $namespace
curl -o $k8sdir/deployment.yaml $deployment
curl -o $k8sdir/checkovconfig.yaml $configmap
curl -o $k8sdir/admissionconfiguration.yaml $admissionregistration
curl -o $k8sdir/service.yaml $service

# the namespace
ns = bridgecrew
kubectl create ns $ns --dry-run=client > $k8sdir/namespace.yaml

# the cluster (repository name)
cluster = $1
# the bridgecrew platform api key 
bc-api-key = $2

# Generate keys into a temporary directory.
echo "Generating TLS certs ..."
/usr/local/opt/openssl/bin/openssl req -x509 -sha256 -newkey rsa:2048 -keyout $certdir/webhook.key -out $certdir/webhook.crt -days 1024 -nodes -addext "subjectAltName = DNS.1:validate.$ns.svc"

kubectl create secret generic admission-tls -n bridgecrew --type=Opaque --from-file=$certdir/webhook.key --from-file=$certdir/webhook.crt --dry-run=client -o yaml > $k8sdir/secret.yaml

kubectl create secret generic bridgecrew-rt-secret \
   --from-literal=BC_API_KEY=$bc-api-key \
   --from-literal=REPO_ID='k8sac/$cluster' -n bridgecrew --dry-run=client > $k8sdir/secret-apikey.yaml

# Create the `bridgecrew` namespace.
echo "Creating Kubernetes objects ..."
kubectl apply -f $k8sdir/namespace.yaml 

# Read the PEM-encoded CA certificate, base64 encode it, and replace the `${CA_PEM_B64}` placeholder in the YAML
# template with it. Then, create the Kubernetes resources.
ca_pem_b64="$(openssl base64 -A <"${certdir}/ca.crt")"
sed -i -e 's@${CA_PEM_B64}@'"$ca_pem_b64"'@g' <"${k8sdir}/admissionconfiguration.yaml" 

# Apply everything in the bridgecrew directory
# kubectl apply -f bridgecrew

# Delete the key directory to prevent abuse (DO NOT USE THESE KEYS ANYWHERE ELSE).
rm -rf "$certdir"

echo "The webhook server has been deployed and configured!"
