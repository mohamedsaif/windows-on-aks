
# Preparing TLS certs
CERT_NAME=win-apps-az-mohamedsaif-com
CERT_CN=win.apps.az.mohamedsaif.com

AKV_NAME=dapr-aks-kv
AKS_NAME=dapr-aks
AKS_RG=dapr-rg

NGINX_NS=nginx
APP_NS=default

KV_MI=$(az aks show -g $AKS_RG -n $AKS_NAME --query addonProfiles.azureKeyvaultSecretsProvider.identity.clientId -o tsv)
echo $KV_MI
TENANT_ID=$(az account show --query tenantId -o tsv)
echo $TENANT_ID

mkdir certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -out certs/$CERT_NAME-tls.crt \
    -keyout certs/$CERT_NAME-tls.key \
    -subj "/CN=*$CERT_CN/O=ingress-tls"

openssl pkcs12 -export -in certs/$CERT_NAME-tls.crt -inkey certs/$CERT_NAME-tls.key  -out certs/$CERT_NAME.pfx
# skip Password prompt

az keyvault certificate import --vault-name $AKV_NAME -n $CERT_NAME -f certs/$CERT_NAME.pfx

# You can bind the certificate to the ingress controller itself or to the application
# Based on your choice, you need to create the nginx/app with appropriate setup

# Installing NGINX
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
kubectl create namespace nginx

# If you will be referencing the cert from the workload, create nginx without the cert volume
helm upgrade --install nginx-ingress ingress-nginx/ingress-nginx \
    -f dapr-nginx-annotations.yaml \
    --set controller.replicaCount=1 \
    --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux \
    --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux \
    --namespace nginx

# If all workload will share certs coming from nginx itself, then attach the cert secret
helm upgrade --install nginx-ingress ingress-nginx/ingress-nginx \
    --namespace nginx \
    --set controller.replicaCount=1 \
    --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux \
    --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux \
    -f - <<EOF
controller:
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/azure-load-balancer-internal: "true"
  podAnnotations:
    dapr.io/enabled: "true"
    dapr.io/app-id: "nginx-ingress"
    dapr.io/app-port: "80"
    dapr.io/sidecar-listen-addresses: 0.0.0.0
  extraVolumes:
      - name: secrets-store-inline
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: $CERT_NAME-tls-spc
  extraVolumeMounts:
      - name: secrets-store-inline
        mountPath: "/mnt/secrets-store"
        readOnly: true
EOF

# Incase of ingress controller managed secret, you can check the creation of the secret
kubectl get secret -n nginx

# Creating the secret CSI (eaither in the nginx namespace or the application namespace)
# Here I'm creating the secret CSI in the application namespace (replace the namespace with nginx if you want it shared)
cat << EOF | kubectl apply -f -
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: $CERT_NAME-tls-spc
  namespace: $APP_NS
spec:
  provider: azure
  secretObjects:                            # secretObjects defines the desired state of synced K8s secret objects
  - secretName: $CERT_NAME-tls-csi
    type: kubernetes.io/tls
    data: 
    - objectName: $CERT_NAME
      key: tls.key
    - objectName: $CERT_NAME
      key: tls.crt
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"          # Set to true for using managed identity
    userAssignedIdentityID: $KV_MI   # Set the clientID of the user-assigned managed identity to use
    keyvaultName: $AKV_NAME                 # the name of the AKV instance
    objects: |
      array:
        - |
          objectName: $CERT_NAME
          objectType: secret
    tenantId: $TENANT_ID                    # the tenant ID of the AKV instance
EOF

# Deploying the application (with reference to the cert secret)
# kubectl apply -f deployment-with-tls-secrets.yaml

cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapplicationfx-http
  namespace: $APP_NS
  labels:
    app: webapplicationfx-http
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webapplicationfx-http
  template:
    metadata:
      labels:
        app: webapplicationfx-http
      annotations:
        dapr.io/enabled: "true"
        dapr.io/app-id: "webapplicationfx"
        dapr.io/app-port: "80"
    spec:
      containers:
      - name: webapplicationfx-http
        image: acrdevgbbmsftweu.azurecr.io/webapplicationfx47:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 80
        env:
        - name: AppVersion
          value: v1.0
        - name: dapr-sb-key
          valueFrom:
            secretKeyRef:
              name: dapr-sb-secret
              key: dapr-sb-key
        - name: dapr-storage-key
          valueFrom:
            secretKeyRef:
              name: dapr-storage-secret
              key: dapr-storage-key
        #envFrom:
        #- configMapRef:
        #    name: webapplicationfx-cm
        volumeMounts:
          - name: secrets-store01-inline
            mountPath: "/inetpub/wwwroot/secrets"
            readOnly: true
          - name: tls-secret
            mountPath: "/certs"
            readOnly: true
        readinessProbe:
          failureThreshold: 3
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 5
          httpGet:
            path: /
            port: 80
            scheme: HTTP
        startupProbe:
          failureThreshold: 3
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 5
          httpGet:
            path: /
            port: 80
            scheme: HTTP
        resources:
            limits:
              memory: 4Gi
              cpu: 1000m
            requests:
              memory: 4Gi
              cpu: 1000m
      tolerations:
      - key: "workload-os"
        operator: "Equal"
        value: "win"
        effect: "NoSchedule"
      nodeSelector:
        workload-type: aspdotnet
      volumes:
        - name: secrets-store01-inline
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: "azure-kvname-user-msi"
        - name: tls-secret
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: $CERT_NAME-tls-spc
EOF

# validation
kubectl get pods -n $APP_NS
kubectl get secrets -n $APP_NS
# should see something like:
# win-apps-az-mohamedsaif-com-tls-csi   kubernetes.io/tls

# If you choose to bind the cert to ingress, create the deployment without the cert secret CSI mount

# Creating a service for the application
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: webapplicationfx-http-service
  namespace: $APP_NS
  annotations:
      service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
  selector:
    app: webapplicationfx-http
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: ClusterIP
EOF

# Creating the ingress resource for:
echo https://web.$CERT_NAME

# ingress resource must be in the same namespace as the application services
cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress-tls
  namespace: $APP_NS
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/rewrite-target: /
    # nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  tls:
  - hosts:
    - web.$CERT_CN
    secretName: $CERT_NAME-tls-csi
  rules:
  - host: web.$CERT_CN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: webapplicationfx-http-service
            port:
              number: 80
EOF

# If you will use dapr for mTLS, we need to create the ingress in the nginx ingress namespace
cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress-tls
  namespace: $NGINX_NS
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    # nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - web.$CERT_CN
    secretName: $CERT_NAME-tls-csi
  rules:
  - host: web.$CERT_CN
    http:
      paths:
      - path: / # This configuration for routing traffic to dapr side car
        pathType: Prefix
        backend:
          service:
            name: nginx-ingress-dapr
            port:
              number: 80
EOF

# Testing

# Option 1: with public IP
SERVICE_EXTERNAL_IP=$(kubectl get service \
    --selector=app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=controller \
    -n nginx \
    -o jsonpath='{.items[*].status.loadBalancer.ingress[0].ip}')
echo $SERVICE_EXTERNAL_IP
curl -v -k --resolve web.$CERT_CN:443:$SERVICE_EXTERNAL_IP https://web.$CERT_CN

# Option 2: with port-forward 443 (nginx ingress port) to 8443 (local machine port)
kubectl port-forward -n nginx service/nginx-ingress-ingress-nginx-controller 8433:443
echo https://web.$CERT_CN:8433
curl -v -k --resolve web.$CERT_CN:8433:127.0.0.1 https://web.$CERT_CN:8433

# Using dapr side car for mTLS
curl -v -k --resolve web.$CERT_CN:8433:127.0.0.1 https://web.$CERT_CN:8433/v1.0/invoke/webapplicationfx.default/method/
curl -v -k --resolve web.$CERT_CN:8433:127.0.0.1 https://web.$CERT_CN:8433/v1.0/invoke/gateway-orchestrator.iot-hub-gateway/method/api/GatewayOrchestrator/version
# https://web.win.apps.az.mohamedsaif.com/v1.0/invoke/webapplicationfx/method

# Diagnostics
# getting logs from nginx ingress controller
NGINX_CONTROLLER_POD=$(kubectl get pods -n $NGINX_NS -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n nginx $NGINX_CONTROLLER_POD -c controller
kubectl logs -n nginx $NGINX_CONTROLLER_POD -c daprd

# If you want to restart the deployment of nginx:
kubectl rollout restart -n nginx deploy/nginx-ingress-ingress-nginx-controller
kgp -n nginx

# clean up
kubectl delete deploy -n $APP_NS webapplicationfx-http
kubectl delete service -n $APP_NS webapplicationfx-http-service
kubectl delete ingress -n $APP_NS web-ingress-tls
kubectl delete SecretProviderClass -n $APP_NS $CERT_NAME-tls-spc
helm uninstall nginx-ingress --namespace $NGINX_NS


kubectl port-forward -n dapr-system service/dapr-dashboard 8080:8080
kubectl exec -it webapplicationfx-http-75fbc897c6-m9l4c -- powershell

Get-WindowsFeature
Get-WebBinding -name "Default Web Site"

Get-PSProvider -PSProvider WebAdministration
Get-ChildItem -Path IIS:\ 
Get-ChildItem -Path IIS:\Sites
Get-ChildItem -Path IIS:\AppPools
Get-ChildItem -Path IIS:\SslBindings

Get-WebBinding -name "Default Web Site"

# Cert loading
$Cert = New-SelfSignedCertificate -dnsName "<Server FQDN>" `
                                  -CertStoreLocation cert:\LocalMachine\My `
                                  -KeyLength 2048 `
                                  -NotAfter (Get-Date).AddYears(1)

$Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2

$Cert.Import("C:\certs\win-apps-az-mohamedsaif-com")

Import-PfxCertificate -FilePath C:\certs\win-apps-az-mohamedsaif-com -CertStoreLocation Cert:\LocalMachine\My
Import-Certificate -FilePath "C:\certs\win-apps-az-mohamedsaif-com" -CertStoreLocation Cert:\LocalMachine\My
$secretRetrieved=(cat C:\certs\win-apps-az-mohamedsaif-com)
$pfxBytes = [System.Convert]::FromBase64String($secretRetrieved)

#Demonstration that you can handle the certificate:

Write-Host $Cert.thumbprint

$x509 = 'System.Security.Cryptography.X509Certificates.X509Store'
$Store = New-Object -TypeName $x509 -ArgumentList 'Root', 'LocalMachine'
$Store.Open('ReadWrite')
$store.Add($Cert)
$Store.Close()