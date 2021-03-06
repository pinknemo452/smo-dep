#!/bin/bash
################################################################################
#   Copyright (c) 2020 AT&T Intellectual Property.                             #
#                                                                              #
#   Licensed under the Apache License, Version 2.0 (the "License");            #
#   you may not use this file except in compliance with the License.           #
#   You may obtain a copy of the License at                                    #
#                                                                              #
#       http://www.apache.org/licenses/LICENSE-2.0                             #
#                                                                              #
#   Unless required by applicable law or agreed to in writing, software        #
#   distributed under the License is distributed on an "AS IS" BASIS,          #
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
#   See the License for the specific language governing permissions and        #
#   limitations under the License.                                             #
################################################################################

echo "===> Starting at $(date)"

# to run in backgroudn nohup:
#   nohup bash -c "./install && date"  &


# where this scrpt is located
SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# where we are when starting
STARTDIR="$(pwd)"

if [ "$1" == "initlocalrepo" ]; then
  echo && echo "===> Initialize local Helm repo"
  rm -rf ~/.helm &&
  helm init -c  # without this step helm serve may not work.
  helm init --stable-repo-url=https://charts.helm.sh/stable
  helm serve &
  helm repo add local http://127.0.0.1:8879
  cd ~
  git clone https://gerrit.onap.org/r/oom.git
  sudo cp -R ~/oom/kubernetes/helm/plugins/ ~/.helm
  cd ~/dep/smo/bin/smo-deploy/smo-oom/kubernetes
  make -e SKIP_LINT=TRUE; make onap -e SKIP_LINT=TRUE
  # take a coffee
  # should see 35 charts
  helm search onap
  cd $WORKINGDIR
  exit 1
fi

echo && echo "===> Cleaning up any previous deployment"
echo "======> Deleting all Helm deployments"
#helm list | sed -e 1d | cut -f1 | xargs helm delete --purge

echo "======> Clearing out all ONAP deployment resources"
kubectl delete ns onap
kubectl get pv --all-namespaces |cut -f1 -d' ' |xargs kubectl delete pv
kubectl get clusterrolebindings | grep onap | cut -f1 -d' '  |xargs kubectl delete clusterrolebindings
rm -rf /dockerdata-nfs

echo "======> Clearing out all RICAUX deployment resources"
kubectl delete ns ricaux
kubectl delete ns ricinfra
rm -rf /opt/data/dashboard-data

echo "======> Clearing out all NONRTRIC deployment resources"
kubectl delete ns nonrtric #edik

echo "======> Preparing for redeployment"
mkdir -p /dockerdata-nfs
mkdir -p /opt/data/dashboard-data
kubectl label --overwrite nodes "$(hostname)" local-storage=enable
kubectl label --overwrite nodes "$(hostname)" aaf-storage=enable
kubectl label --overwrite nodes "$(hostname)" portal-storage=enable

echo "======> Preparing working directory"
mkdir -p smo-deploy
cd smo-deploy
WORKINGDIR=$(pwd)
CURDIR="$(pwd)"


echo && echo "===> Deploying OAM (ONAP Lite)"
if [ ! -d smo-oom ]
then
  echo "======> Building ONAP helm charts.  !! This will take very long time (hours)."
  cat << EOF >> override-oam.yaml
global:
  aafEnabled: false
  masterPassword: Berlin1234!
cassandra:
  enabled: false
mariadb-galera:
  enabled: true
aaf:
  enabled: false
aai:
  enabled: false
appc:
  enabled: false
clamp:
  enabled: false
cli:
  enabled: false
consul:
  enabled: true
contrib:
  enabled: false
dcaegen2:
  enabled: false
dmaap:
  enabled: true
  message-router:
    enabled: true
  dmaap-bc:
    enabled: false
  dmaap-dr-node:
    enabled: false
  dmaap-dr-prov:
    enabled: false
esr:
  enabled: false
log:
  enabled: false
sniro-emulator:
  enabled: false
oof:
  enabled: false
msb:
  enabled: true
multicloud:
  enabled: false
nbi:
  enabled: false
policy:
  enabled: false
pomba:
  enabled: false
portal:
  enabled: false
robot:
  enabled: false
sdc:
  enabled: false
sdnc:
  enabled: true
  replicaCount: 1
  config:
    sdnr:
      sdnrwt: true
      sdnronly: true
      sdnrmode: dm
      mountpointRegistrarEnabled: true
      mountpointStateProviderEnabled: true
  cds:
    enabled: false
  dmaap-listener:
    enabled: true
  ueb-listener:
    enabled: false
  sdnc-portal:
    enabled: false
  sdnc-ansible-server:
    enabled: false
  dgbuilder:
    enabled: false
  sdnc-web:
    enabled: false
so:
  enabled: false
uui:
  enabled: false
vfc:
  enabled: false
vid:
  enabled: false
vnfsdk:
  enabled: false
modeling:
  enabled: false
EOF

  git clone https://gerrit.onap.org/r/oom.git
  sudo cp -R ~/oom/kubernetes/helm/plugins/ ~/.helm
  cd oom/kubernetes
  make -e SKIP_LINT=TRUE; make onap -e SKIP_LINT=TRUE
  # take a coffee
  # should see 35 charts
  helm search onap

  cd $WORKINGDIR
fi


echo "======> Deploying ONAP-lite"
helm deploy dev local/onap --namespace onap -f ./override-oam.yaml

echo "======> Waiting for ONAP-lite to reach operatoinal state"
NUM_SDNR_RUNNING_PODS="0"
NUM_MR_RUNNING_PODS="0"

while [ "$NUM_MR_RUNNING_PODS" -lt "7" ] || [ "$NUM_SDNR_RUNNING_PODS" -lt "7" ]
do
  sleep 5
  NUM_SDNR_RUNNING_PODS=$(kubectl get pods --all-namespaces | grep "sdn[\/0-9a-z \-]*Running" | wc -l)
  NUM_SDNC_COMPLETED_JOBS=$(kubectl get pods --all-namespaces | grep "sdn[\/0-9a-z \-]*Completed" | wc -l)
  NUM_MR_RUNNING_PODS=$(kubectl get pods --all-namespaces | grep "message-router[\/0-9a-z \-]*Running" | wc -l)

  echo "${NUM_SDNR_RUNNING_PODS}/7 SDNC-SDNR pods and ${NUM_MR_RUNNING_PODS}/7 Message Router pods running"
done


echo && echo "===> Deploy NONRTRIIC"
git clone http://gerrit.o-ran-sc.org/r/it/dep smo-dep -b bronze
cd smo-dep

cd demos/bronze
env SMO_IP=192.168.233.75 RIC_IP=192.168.233.232 ./__config-ip.sh < README.txt
cd ../..

REPOROOTDIR=$(git rev-parse --show-toplevel)



#edik
rm ~/dep/smo/bin/smo-deploy/smo-dep/nonrtric/helm/nonrtric/requirements.lock

cd bin
./deploy-nonrtric -f ~/dep/smo/bin/smo-deploy/smo-dep/RECIPE_EXAMPLE/NONRTRIC/example_recipe.yaml
echo "======> Waiting for NONRTRIC to reach operatoinal state"
NUM_A1C_RUNNING_PODS="0"
NUM_A1SIM_RUNNING_PODS="0"
NUM_CP_RUNNING_PODS="0"
NUM_DB_RUNNING_PODS="0"
NUM_PMS_RUNNING_PODS="0"

while [ "$NUM_A1C_RUNNING_PODS" -lt "1" ] || [ "$NUM_CP_RUNNING_PODS" -lt "1" ] || \
      [ "$NUM_DB_RUNNING_PODS" -lt "1" ]|| [ "$NUM_PMS_RUNNING_PODS" -lt "1" ] || \
      [ "$NUM_A1SIM_RUNNING_PODS" -lt "4" ]
do
  sleep 5
  NUM_A1C_RUNNING_PODS=$(kubectl get pods -n nonrtric | grep "a1controller[\/0-9a-z \-]*Running" | wc -l)
  NUM_A1SIM_RUNNING_PODS=$(kubectl get pods -n nonrtric | grep "a1-sim[\/0-9a-z \-]*Running" | wc -l)
  NUM_CP_RUNNING_PODS=$(kubectl get pods -n nonrtric  | grep "controlpanel[\/0-9a-z \-]*Running" | wc -l)
  NUM_DB_RUNNING_PODS=$(kubectl get pods -n nonrtric  | grep "db[\/0-9a-z \-]*Running" | wc -l)
  NUM_PMS_RUNNING_PODS=$(kubectl get pods -n nonrtric  | grep "policymanagementservice[\/0-9a-z \-]*Running" | wc -l)

  echo "${NUM_A1C_RUNNING_PODS}/1 A1Controller pods, ${NUM_CP_RUNNING_PODS}/1 ControlPanel pods, "
  echo "${NUM_DB_RUNNING_PODS}/1 DB pods, ${NUM_PMS_RUNNING_PODS}/1 PolicyManagementService pods, "
  echo "and ${NUM_A1SIM_RUNNING_PODS}/4 A1Sim pods  running"
done



echo && echo "===> Deploying VES collector and its ingress"
kubectl create ns ricinfra

cd ${REPOROOTDIR}/ric-aux/helm/infrastructure
helm dep update
cd ..
helm install -f ${REPOROOTDIR}/RECIPE_EXAMPLE/AUX/example_recipe.yaml --name bronze-infra --namespace ricaux ./infrastructure

cd ${REPOROOTDIR}/ric-aux/helm/ves
helm dep update
cd ..
helm install -f ${REPOROOTDIR}/RECIPE_EXAMPLE/AUX/example_recipe.yaml --name bronze-ves --namespace ricaux ./ves


# edit RECIPE_EXAMPLE/AUX/example_recipe.yaml file
#./bin/prepare-common-templates
#cd ric-aux/bin
#./install -f ${REPOROOTDIR}/RECIPE_EXAMPLE/AUX/example_recipe.yaml -c "ves"

cd $STARTDIR
kubectl get pods --all-namespaces

echo "===> Completing at $(date)"
