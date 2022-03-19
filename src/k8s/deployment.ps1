kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# Using Key Vault secrets
kubectl apply -f web-secret-provider.yaml
kubectl apply -f deployment-with-secrets.yaml
# Validation
kubectl exec -it webapplicationfx-http-5c8c7b6d65-s9lp7 -- cmd
dir
cd secrets
type dapr-sb-key

# mTLS (https://docs.dapr.io/operations/security/mtls/)
kubectl get configurations/daprsystem --namespace dapr-system -o yaml
kubectl logs --selector=app=dapr-sentry --namespace dapr-system

# Installing NGINX
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
kubectl create namespace nginx
helm install upgrade nginx-ingress ingress-nginx/ingress-nginx \
    -f dapr-nginx-annotations.yaml \
    --set controller.replicaCount=2 \
    --namespace nginx

# Preparing TLS certs
AKV_NAME=dapr-aks-kv
CERT_NAME=win-apps-az-mohamedsaif-com
TENANT_ID=$(az account show --query tenantId -o tsv)
echo $TENANT_ID
KV_MI=$(az aks show -g $AKS_RG -n $AKS_NAME --query addonProfiles.azureKeyvaultSecretsProvider.identity.clientId -o tsv)
echo $KV_MI
mkdir certs

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -out certs/$CERT_NAME-tls.crt \
    -keyout certs/$CERT_NAME-tls.key \
    -subj "/CN=*.win.apps.az.mohamedsaif.com/O=ingress-tls"


openssl pkcs12 -export -in certs/$CERT_NAME-tls.crt -inkey certs/$CERT_NAME-tls.key  -out certs/$CERT_NAME.pfx
# skip Password prompt

az keyvault certificate import --vault-name $AKV_NAME -n $CERT_NAME -f certs/$CERT_NAME.pfx

cat<< EOF kubectl apply -f -

EOF