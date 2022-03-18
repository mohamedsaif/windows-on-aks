# Windows containers basic deployment

This guide focus on getting and AKS cluster that support Windows and deploy locally sourced application.

## Deployment variables

Here I'm setting some variables for consistent deployment

```bash
# Variables
PREFIX=windows-containers
AKS_RG=$PREFIX-rg
AKS_NAME=$PREFIX-aks
LOCATION=westeurope
WIN_ADMIN=$AKS_NAME-admin
ACR_NAME=windows${RANDOM}acr
echo $ACR_NAME
```

## Deploy Azure Container Registry

In order to deploy custom workloads to AKS, we might need Azure Container Registry (ACR) to push our private images to their so AKS can pull it at deployment time.

To create ACR, you can use again Azure CLI or Azure Portal

```bash

az acr create --name $ACR_NAME -g AKS_RG -l $LOCATION --sku Standard

```

## Deploy AKS

Using the Azure Portal or Azure CLI to created an AKS cluster:

```bash

PREFIX=windows-containers
AKS_RG=$PREFIX-rg
AKS_NAME=$PREFIX-aks
LOCATION=westeurope
WIN_ADMIN=$AKS_NAME-admin

az group create --name $AKS_RG --location LOCATION

az aks create \
    --resource-group $AKS_RG \
    --name $AKS_NAME \
    --node-count 2 \
    --enable-addons monitoring \
    --generate-ssh-keys \
    --windows-admin-username $WIN_ADMIN \
    --vm-set-type VirtualMachineScaleSets \
    --attach-acr $ACR_NAME
    --network-plugin azure

az aks nodepool add \
    --resource-group $AKS_RG \
    --cluster-name $AKS_NAME \
    --os-type Windows \
    --name npwin \
    --node-count 1

# OPTIONAL: install kubectl CLI
az aks install-cli

az aks get-credentials --resource-group $AKS_RG --name $AKS_NAME

kubectl get nodes -o wide

```

## Deploy custom application

You need to have both the source code and a dockerfile that includes the container image build instructions in your project.

>NOTE: You can simply right click on a Visual Studio project and click add Docker support to generate standard file like the one in this template

```bash

# Set folder context to the project in the terminal and execute the following (it will take few mins)
az acr build -r acrdevgbbmsftweu https://github.com/Azure/acr-builder.git -t dotnet/webapp:{{.Run.ID}} -t dotnet/webapp:latest -f Windows.Dockerfile --platform windows

```

Now with the image dotnet/webapp:latest successfully pushed to the registry, we are good to deploy the application