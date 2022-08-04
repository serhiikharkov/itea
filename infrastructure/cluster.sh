#!/bin/bash
##########################################################
#Vars                                                    #
#########################################################
############  KSI IT creds ##############################
#########################################################
KSI_SUB='************************************'
KSI_ACR='ksidopsaks'
KSI_SP_ID='***************************************'
KSI_SP_SEC='*************************************'
KSI_URL='itea.ksi.kiev.ua'

########################################################
########################################################
RG='itea-rg'
NS_env='develop'
ClusterName='aks-itea'

URLsite=$KSI_URL
SubsciptID=$KSI_SUB
SP_ID=$KSI_SP_ID
SP_SECRET=$KSI_SP_SEC
ACRname=$KSI_ACR


########################################################
#NET
#https://docs.microsoft.com/en-us/azure/aks/configure-kubenet
#IP_docker_bridge_address       10.250.112.1/24         -- used for docker containers inside pods
#IP_dns_service_ip              10.250.110.5            -- used for DNS resolving services and deployments
#IP_service_cidr                10.250.110.0/24         -- used for ip addressing services and deployments
#$VnetName and $VnetSub         10.250.111.0/24         -- used for Net addressing nodes, podes of AKS
#$VnetSub                       10.250.111.0/25         -- used for Subnet addressing nodes, podes of AKS


VnetName=$ClusterName'-Vnet'
VnetSub=$ClusterName'-Vsubnet'
Region='westeurope'
PublicIPName='PublicIP-'$ClusterName
ACRur=/subscriptions/$SubsciptID/resourceGroups/$ResGroup/providers/Microsoft.ContainerRegistry/registries/$ACRname
az account set --subscription $SubsciptID

az_network_vnet='10.250.204.0/24'
az_network_vnet_sub='10.250.204.0/24'

IP_dns_service_ip='172.16.1.5'
IP_service_cidr='172.16.1.0/24'

IP_docker_bridge_address='172.16.2.0/24'

IP_pod_net_CIDR='172.16.3.0/24'

echo "####################################################################"
echo "#############SERVICE_PRINCIPAL_Account  ############################"
echo "####################################################################"
#https://docs.microsoft.com/en-us/cli/azure/ad/sp?view=azure-cli-latest#az_ad_sp_show
###########################################################################

echo "####################################################################################"
echo "############################## Show SP information #################################"
echo "####################################################################################"
echo "SP_ID            ------- "$SP_ID
echo "SP_SECRET        ------- "$SP_SECRET
echo "Azure Sunscription   --- "$SubsciptID
az ad app show  --id $SP_ID --query '[displayName, appId, objectType, passwordCredentials[0].endDate, passwordCredentials[0].startDate]' -o tsv
###########################################################################################
echo "sleeping 2s"
sleep 2s
#
#Set Service Principial Account
RG_ID=$(az group show --name $RG | jq .id -r)
echo "ID Resource Group $RG   "$RG_ID
az role assignment create --assignee  $SP_ID  --scope $RG_ID --role "Network Contributor"
############################################################################################
#Create new Vnet and create two subnets inside that Vnet, for the Application Gateway and Kubernetes each.
############################################################################################

az network vnet create --name $VnetName --resource-group $RG --location $Region --address-prefix $az_network_vnet
az network vnet subnet create --name $VnetSub --resource-group $RG --vnet-name $VnetName --address-prefix $az_network_vnet_sub

#############################################################################################
#                          Create Cluster                                                   #
#############################################################################################
##--node-vm-size Standard_D2as_v4
az aks create \
    --name $ClusterName \
    --resource-group $RG \
    --enable-managed-identity \
    --location $Region \
    --node-count 1 \
    --zones 1 2 3\
    --node-vm-size Standard_B2s \
    --network-plugin azure \
    --vnet-subnet-id /subscriptions/$SubsciptID/resourceGroups/$RG/providers/Microsoft.Network/virtualNetworks/$VnetName/subnets/$VnetSub \
    --generate-ssh-keys \
    --kubernetes-version 1.23.8 \
    --network-plugin azure \
    --service-cidr $IP_service_cidr \
    --docker-bridge-address $IP_docker_bridge_address \
    --dns-service-ip $IP_dns_service_ip  \
    --dns-name-prefix $ClusterName \
    --service-principal $SP_ID \
    --client-secret $SP_SECRET \
    --attach-acr $ACRname

echo "sleeping 15s"
sleep 15s
#############################################################################################
###################### Create public IP #####################################################
#############################################################################################
Cluster_nodeResourceGroup=$(az aks show --resource-group $RG --name $ClusterName | jq .nodeResourceGroup -r)
echo "Cluster_nodeResourceGroup      ---> "$Cluster_nodeResourceGroup

#create Public IP for traefik and ballancer AKS cluster
PublicIPName=$ClusterName'-PublicIP'
az network public-ip create \
     --resource-group $Cluster_nodeResourceGroup \
     --name $PublicIPName \
     --allocation-method Static \
     --location $Region \
     --sku standard \
     --version IPv4

#--public IP that has been created as a part of the previous steps so that-------
#--Kubernetes can assign that IP to the Traefik Service--------------------------
PublicIP=$(az network public-ip show -g $Cluster_nodeResourceGroup -n $PublicIPName | jq .ipAddress -r)
echo "PublicIP       "$PublicIP
PublicIP_ID=$(az network public-ip show -g $Cluster_nodeResourceGroup -n $PublicIPName | jq .id -r)
echo "PublicIP_ID    "$PublicIP_ID
az role assignment create --assignee  $SP_ID  --scope $PublicIP_ID --role "Network Contributor"
#############################################################################################
#Set outbound IP cluster for ballanser AKS cluster
az aks update \
    --resource-group $RG \
    --name $ClusterName \
    --load-balancer-outbound-ips $PublicIP_ID

az aks get-credentials --resource-group $RG --name $ClusterName


echo "######################################################################################"
echo "######################################################################################"
echo "############################ namespaces ##############################################"
echo "######################################################################################"
echo "######################################################################################"

kubectl create namespace logdna
kubectl create namespace traefik
kubectl create namespace $NS_env

echo "######################################################################################"
echo "#####################################################################################"
echo "###########################   traefik   ##############################################"
echo "######################################################################################"
echo "######################################################################################"

#creat traefik use publik ipand Resourse Groupe of this IP
sudo rm traefik-values.yml -f

cat <<  EOF >  traefik-values.yml
#------------------------------------
#for deploying Traefik, the static configuration
additionalArguments:
logs:
  general:
    level: DEBUG
  access:
    enable: true
    format: json
additionalArguments:
  - "--certificatesresolvers.elg.acme.tlschallenge=true"
  - "--certificatesresolvers.elg.acme.email=elg@elg.com"
  - "--certificatesresolvers.elg.acme.storage=/data/acme.json"
  - "--metrics.prometheus=true"
  - "--pilot.token=1ffa4876-8536-4f30-8045-5c16dcf58f02"
  - "--api.dashboard=true"
deployment:
  replicas: 1
service:
  spec:
    loadBalancerIP: $PublicIP
  annotations:
    "service.beta.kubernetes.io/azure-load-balancer-resource-group": $Cluster_nodeResourceGroup
EOF
cat traefik-values.yml
#----------------------------------------------------
helm repo add traefik https://helm.traefik.io/traefik
helm repo update
helm upgrade --install traefik traefik/traefik \
 -f traefik-values.yml \
 -n traefik \
 --set dashboard.enabled=true

##########################################################################################################################################
echo "######################################################################################"
echo "#####################    Traefik dashboar     ########################################"
echo "######################################################################################"
yum install httpd-tools -y

export TRAEFIK_UI_USER=admin
export TRAEFIK_UI_PASS=dashboard
DESTINATION_FOLDER='traefik-ui-creds'
# Backup credentials to local files (in case you'll forget them later on)
mkdir -p ${DESTINATION_FOLDER}
echo $TRAEFIK_UI_USER >> $DESTINATION_FOLDER/traefik-ui-user.txt
echo $TRAEFIK_UI_PASS >> $DESTINATION_FOLDER/traefik-ui-pass.txt

htpasswd -Bbn ${TRAEFIK_UI_USER} ${TRAEFIK_UI_PASS} \
    > ${DESTINATION_FOLDER}/htpasswd

cd ${DESTINATION_FOLDER}
kubectl create secret generic traefik-dashboard-auth-secret \
   --from-file=htpasswd \
   --namespace traefik
#########################################################################################

cat <<  EOF >  traefik-dashboard.yml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-dashboard-https
  namespace: traefik
spec:
  entryPoints:
    - websecure
  routes:
    - kind: Rule
      match: Host(\`$URLsite\`) && (PathPrefix(\`/api\`) || PathPrefix(\`/dashboard\`))
      services:
        - name: api@internal
          kind: TraefikService
      middlewares:
        - name: traefik-dashboard-auth # Referencing the BasicAuth middleware
          namespace: traefik
  tls:
    certResolver: itea
---
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: traefik-dashboard-auth
  namespace: traefik
spec:
  basicAuth:
    secret: traefik-dashboard-auth-secret
EOF
echo "#########################################################################################"
cat traefik-dashboard.yml
kubectl apply -f traefik-dashboard.yml


cd ..

echo "######################################################################################"
echo "################################  logDNA   ###########################################"
echo "######################################################################################"
#LOGDNA_INGESTION_KEY=9924e0b87654c38a43022b41d4aebcf2
#helm repo add logdna https://assets.logdna.com/charts
#helm install --set logdna.key=$LOGDNA_INGESTION_KEY,logdna.tags=$ClusterName my-release logdna/agent --namespace logdna
# helm uninstall  my-release logdna/agent


echo "######################################################################################"
echo "############################### test env #############################################"


 echo " kubectl apply -f deployment-api-IO.yaml -n $NS_env      "
 echo " kubectl apply -f deployment-redis.yml -n $NS_env        "
 echo " kubectl apply -f deployment-ui-IO.yaml -n $NS_env       "
 echo " kubectl apply -f CI-services.yml -n $NS_env             "
 echo " kubectl apply -f traefik-route_$URLsite.yml -n $NS_env  "


echo "######################################################################################"
echo "##################### Have create AKS cluster ########################################"
echo "######################################################################################"
echo -e "\t in RG             >\t"$RG
echo -e "\t Cluster Name      >\t"$ClusterName
echo -e "\t Subscipt ID       >\t"$SubsciptID
echo -e "\t ACR Name          >\t"$ACRname
#echo -e "\t UserAzACR         >\n 00000000-0000-0000-0000-000000000000"
#echo -e "\t TockenAzACR       >\n"$TockenAzACR
echo "-------------------traefik------------------------------------------------------------"
echo -e "\t Traefik site      >\t https://$URLsite/dashboard/#"
echo -e "\t Traefik User      >\t "$TRAEFIK_UI_USER
echo -e "\t Traefik pass      >\t "$TRAEFIK_UI_PASS
echo "-------------------NET----------------------------------------------------------------"
echo -e "\t PublicIP Name     >\t"$PublicIPName
echo -e "\t Public IP         >\t"$PublicIP
echo -e "\t PublicIP ID       >\t"$PublicIP_ID
echo -e "\t Cluster Name      >\t"$ClusterName
echo "----------SERVICE_PRINCIPAL_Account---------------------------------------------------"
echo -e "\t SP ID             >\t"$SP_ID
echo -e "\t SP SECRET         >\t"$SP_SECRET
