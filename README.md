# Setup arc-enabled microk8s cluster along with flux configurations 
This repository has a script to provision an edge device with required components like microk8s, flux and enables the cluster with azure-arc for manageability from azure cloud.

This repo has a configuration template file `.env-template` which can be used to create a `.env` file. 

`.env` file need to have values for the required parameters.

```
SITE_NAME=''              #Name of git config folder containing your site resources.
AZ_TEANANT_ID=''          #Azure teanant id.
AZ_SP_ID=''               #Azure service principal id.
AZ_SP_SECRET=''           #Azure service principal secret.
AZ_ARC_RESOURCEGROUP=''   #Azure resource group for your arc-cluster
AZ_ARC_RESOURCEGROUP_LOCATION='' #Azure location for your resources
GITOPS_REPO=''            #Name of the git repository
GITOPS_PAT=''             #Your PAT token
GITOPS_BRANCH=''          #Your git branch
```

There is `script.sh` file which reads `.env` file for configurations and then provisions the device with required components and connects the microk8s cluster with azure-arc.

### How to run this script
* Copy the .env-template to .env file and set all the appropriate values in the variables listed in .env file
* You'll need to add site name, Azure service principal for setting up Arc, gitops repo, branch name and token for flux.
* Run this script using ./setup.sh



For more details refer to [this blog post](https://sapinder.medium.com/automating-arc-enabled-microk8s-with-flux-setup-on-ubuntu-edge-devices-91c364228a3).
