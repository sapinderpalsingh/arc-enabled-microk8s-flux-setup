#!/bin/bash
set -o errexit
#set -o nounset
set -o pipefail

#Load environment variables from the file
export $(grep -v '^#' .env | xargs)

# Check for Az Cli, env variables
check_vars()
{
    var_names=("$@")
    for var_name in "${var_names[@]}"; do
        [ -z "${!var_name}" ] && echo "$var_name is unset." && var_unset=true
    done
    [ -n "$var_unset" ] && exit 1
    return 0
}

check_vars SITE_NAME AZ_SP_ID AZ_SP_SECRET GITOPS_REPO GITOPS_PAT GITOPS_BRANCH AZ_ARC_RESOURCEGROUP AZ_ARC_RESOURCEGROUP_LOCATION AZ_TEANANT_ID

if command -v az -v >/dev/null; then
     printf "\n AZ CLI is present ✅ \n"
else
     printf "\n AZ CLI could not be found ❌ \n"
     exit
fi


printf "\n Starting microk8s installation 🚧 \n"

sudo systemctl start snapd.socket
# Install & set up microk8s
sudo snap install microk8s --classic

# sleep to avoid timing issues
sleep 10

# Check microk8s status
sudo microk8s status --wait-ready
printf '\n microk8s installed successfully ✅'


# Install Kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Set up config for kubectl
sudo rm -rf ~/.kube
mkdir ~/.kube
sudo microk8s config > ~/.kube/config
printf '\n Kubectl installed successfully ✅ \n'

# Enable microk8s extensions - DNS, HELM
sudo microk8s enable dns
sleep 5
kubectl wait --for=condition=containersReady pod -l k8s-app=kube-dns -n kube-system
printf '\n microk8s dns enabled successfully ✅\n'

printf "Installing flux 🚧 \n"
# Install Flux
curl -s https://fluxcd.io/install.sh | sudo bash
. <(flux completion bash)

# Setup flux
rm -rf $HOME/$GITOPS_REPO
git clone https://$GITOPS_PAT@github.com/$GITOPS_REPO $HOME/$GITOPS_REPO

cd $HOME/$GITOPS_REPO

git checkout $GITOPS_BRANCH

kubectl apply -f "clusters/$SITE_NAME/flux-system/flux-system/controller.yaml" 
sleep 3 

flux create secret git gitops -n flux-system \
--url "https://github.com/$GITOPS_REPO" \
--password "$GITOPS_PAT" \
--username gitops

kubectl apply -k "clusters/$SITE_NAME/flux-system/flux-system" 

printf '\n Flux installed successfully ✅\n'

# Switching Back to Home Directory 
cd $HOME

##### ARC region ######

printf "\n Logging in Azure using Service Principal 🚧 \n"
# Az Login using SP
az login --service-principal -u $AZ_SP_ID  -p  $AZ_SP_SECRET --tenant $AZ_TEANANT_ID

# Arc setup 
az extension add --name connectedk8s
az extension add -n k8s-extension

az provider register --namespace Microsoft.Kubernetes
az provider register --namespace Microsoft.KubernetesConfiguration
az provider register --namespace Microsoft.ExtendedLocation

# Check for existing resource group
if [ $(az group exists --name $AZ_ARC_RESOURCEGROUP) == false ]; then
    az group create --name $AZ_ARC_RESOURCEGROUP --location $AZ_ARC_RESOURCEGROUP_LOCATION --output table
    printf "\n Resource group $AZ_ARC_RESOURCEGROUP created ✅\n"
fi

printf "\n Connecting to Azure Arc 🚧 \n"
az connectedk8s connect --name $SITE_NAME --resource-group $AZ_ARC_RESOURCEGROUP

# Generate token to connect to Azure k8s cluster
ADMIN_USER=$(kubectl get serviceaccount admin-user -o jsonpath='{$.metadata.name}' --ignore-not-found)
if [ -z "$ADMIN_USER" ]; then
    printf "\n Creating service account 🚧 \n"
    kubectl create serviceaccount admin-user
else
    printf "\n Service account already exist. \n"
fi

CLUSTER_ROLE_BINDING=$(kubectl get clusterrolebinding admin-user-binding -o jsonpath='{$.metadata.name}' --ignore-not-found)
if [ -z "$CLUSTER_ROLE_BINDING" ]; then
    printf "\n Creating cluster role binding 🚧 \n"
    kubectl create clusterrolebinding admin-user-binding --clusterrole cluster-admin --serviceaccount default:admin-user
else
    printf "\n Cluster role binding already exist. \n"     
fi

# Generating a secret
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: admin-user
  annotations:
    kubernetes.io/service-account.name: admin-user
type: kubernetes.io/service-account-token
EOF

TOKEN=$(kubectl get secret admin-user -o jsonpath='{$.data.token}' | base64 -d | sed $'s/$/\\\n/g')

printf "\n ####### Token to connect to Azure ARC starts here ######## \n"
printf $TOKEN
printf "\n ####### Token to connect to Azure ARC ends here   ######### \n"
echo $TOKEN > token.txt
printf "\n Token is saved at token.txt file \n"

