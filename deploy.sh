# ==============================================================================
## DESCRIPTION: Deploy Kubernetes.
## NAME: deploy.sh
## AUTHOR: Cloud Team
## DATE: 23.04.2020
## VERSION: 2.0
## RUN:
##      > chmod a+x ./deploy.sh && bash deploy.sh -h
# ==============================================================================

# High Intensity
BLACK="\033[0;90m"       # Black
RED="\033[0;91m"         # Red
GREEN="\033[0;92m"       # Green
YELLOW="\033[0;93m"      # Yellow
BLUE="\033[0;94m"        # Blue
PURPLE="\033[0;95m"      # Purple
CYAN="\033[0;96m"        # Cyan
NC="\033[0;97m"          # White

# ==============================================================================
# VALUES
# ==============================================================================

CUT_START=1
CUT_END=
INDEX=1

OS=`uname`
[ "${OS}" = "Linux" ] && DATE_CMD="date" || DATE_CMD="gdate"
DATE_INFO=$(${DATE_CMD} +"%Y-%m-%d %T")
DATE_INFO_SHORT=$(${DATE_CMD} +"%A %B")
USER=$(whoami)

[ $(echo "${CI_COMMIT_REF_SLUG}" | grep "feature") ] && \
  CURRENT_BRANCH="feature" || CURRENT_BRANCH="develop"

if [ -f "${CI_PROJECT_DIR}/values.yml" ]; then
  YML="${CI_PROJECT_DIR}/values.yml"
elif [ -f "${CI_PROJECT_DIR}/values.yaml" ]; then
  YML="${CI_PROJECT_DIR}/values.yaml"
fi

FILE=${YML}
RELEASE_NAME="${CI_PROJECT_PATH_SLUG}-${CI_COMMIT_REF_SLUG}"
SPLIT_RELEASE_NAME=$(echo "${RELEASE_NAME}" | tr "-" "\n")
LENGTH_RELEASE_NAME=$(echo -n "${RELEASE_NAME}" | wc -m)

# ==============================================================================
# FUNCTIONS
# ==============================================================================

function Status() {
  echo -e "[DEPLOY]: ${1}"
}

function Welcome() {
  echo -e "\n"
  echo "Kubernetes Deploy" | figlet
  echo -e "\n-------------------------------------------------"
  echo "* Welcome ${USER}! It's now ${DATE_INFO_SHORT}"
  echo -e "* ${DATE_INFO}"
  echo -e "* System - ${OS}"
  echo -e "*"
  echo -e "* Autor: ${YELLOW}Cloud Team${YELLOW}${NC}"
  echo -e "* Description: ${BLUE}Script to help with Kubernetes Deploys${BLUE}${NC}"
  echo -e "* Version: ${YELLOW}2.0.0${YELLOW}${NC}"
  echo -e "-------------------------------------------------\n"
}

function Help() {
  local PROGNAME=$(basename ${0})
  echo -e "\n${CYAN}Script $PROGNAME: By ${YELLOW}Cloud Team.${NC}"
  cat <<EOF
Description: Kubernetes Deploy from Bash.
Flags:
  -n, n, namespace, --namespace                     Kubernetes Namespace.
  -h, h, help, --help                               Show this help message.
  -slack-channel, slack-channel, --slack-channe     Slack Channel Name.
  -slack-token, slack-token, --slack-token          Slack CLI Token.
EOF
}

function AssertIsInstalled() {
  local readonly PACKAGE=$(command -v "${1}")
  MESSAGE="\n${RED}ERROR: The binary '${PACKAGE}' is required by this script but is not installed or in the system's PATH.${NC}\n"
  [ ! ${PACKAGE} ] && { echo -e ${MESSAGE}; exit 1; } || echo -e "\n${YELLOW}The Package ${1} alredy exist!${NC}"
}

function CheckGeneralVariables() {
  [ ! "${RELEASE_NAME}" ] && [ "${RELEASE_NAME}" == "" ] || [ "${RELEASE_NAME}" == "-" ] && \
      { echo -e "\n${RED}Variable Release Name/Catalog Name is empty or not exist. Bye Bye!${NC}"; exit 1; } || \
          echo -e "${GREEN}Variable Release Name/Catalog Name exist and is not empty${NC}"
  [ ! "${NAMESPACE}" ] && [ "${NAMESPACE}" == "" ] && \
      { echo -e "\n${RED}Variable Namespace is empty or not exist. Bye Bye!${NC}"; exit 1; } || \
          echo -e "${GREEN}Variable Namespace exist and is not empty${NC}"
  [ ! "${FILE}" ] && [ "${FILE}" == "" ] && \
      { echo -e "\n${RED}Variable YML File is empty or not exist. Bye Bye!${NC}"; exit 1; } || \
          echo -e "${GREEN}Variable YML File exist and is not empty${NC}"
}

function SendSlackMessage() {
  local PRETEXT=${1}
  local TEXT=${2}
  if [ ! "${SLACK_CHANNEL}" ] && [ "${SLACK_CHANNEL}" == "" ] && [ ! "${SLACK_CLI_TOKEN}" ] && [ "${SLACK_CLI_TOKEN}" == "" ]; then
    Status "No Slack Messages!"
  else
    slack chat send --pretext ${PRETEXT} \
      --title "Information:" \
      --text ${TEXT} \
      --channel ${SLACK_CHANNEL} \
      --token ${SLACK_CLI_TOKEN} 2> /dev/null
  fi
}

function FindHelmRelease() {
  Status "${BLUE}Filter Helm Releases...${NC}" && \
  for RELEASE in $(helm list -n ${NAMESPACE} -d --short); do if [ "${1}" == "${RELEASE}" ]; then echo "${1}"; else continue; fi; done
}

function HelmInstall() {
  Status "${YELLOW}Installing Helm Chart ${1}...${NC}"
  helm install --wait -n ${NAMESPACE} ${1} ${HELM_CHART_DIR} \
    --set devops.branch=${CI_COMMIT_REF_SLUG} \
    --set devops.project=${CI_PROJECT_PATH_SLUG} \
    --set devops.microService=${1} \
    --set image.repository=${IMAGE} \
    --set devops.provider=${PROVIDER} \
    -f ${FILE}
}

function HelmUpgrade() {
  Status "${YELLOW}Upgrading Helm Chart: ${1}...${NC}"
  helm upgrade --install --wait -n ${NAMESPACE} ${1} ${HELM_CHART_DIR} \
    --set devops.branch=${CI_COMMIT_REF_SLUG} \
    --set devops.project=${CI_PROJECT_PATH_SLUG} \
    --set devops.microService=${1} \
    --set image.repository=${IMAGE} \
    --set devops.provider=${PROVIDER} \
    -f ${FILE}
}

function HelmUpgradeInstall() {
  HELM_RELEASE_EXIST=$(FindHelmRelease ${1})
  if [ ! "${HELM_RELEASE_EXIST}" ] || [ "${HELM_RELEASE_EXIST}" == "" ]; then 
    HelmInstall ${1}
  else
    Status "${YELLOW}The release ${1} alredy exist!${NC}" && HelmUpgrade ${1}
  fi
}

function FindFeatureIndex() {
  for VALUE in ${SPLIT_RELEASE_NAME[@]}; do 
    if [ "${VALUE}" == "feature" ]; then CUT_END=${INDEX}; fi
    INDEX=$(expr ${INDEX} + 1)
  done
}

function DeployDevelop() {
  IMAGE=${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHORT_SHA}
  HELM_CHART_DIR="/root/charts/deploy-develop"
  if [ ! "${FILE}" ] && [ "${FILE}" == "" ]; then FILE="/root/charts/deploy-develop/values.yaml"; fi
  Status "Context - Develop Branch"
  Status "Image Name Develop: ${IMAGE}"
  Status "Helm Chart DIR Develop: ${HELM_CHART_DIR}"
  Status "Values File Develop: ${FILE}"
  if [ ${LENGTH_RELEASE_NAME} -le 53 ]; then
    NORMALIZE_RELEASE_NAME_DEVELOP=${RELEASE_NAME}
    Status "Normalize Release Name Develop: ${NORMALIZE_RELEASE_NAME_DEVELOP}"
    Status "Helm Upgrade-Install Develop"
    HelmUpgradeInstall ${NORMALIZE_RELEASE_NAME_DEVELOP}
  else
    Status "${RED}Error Deploy in Develop - Number of characters exceeded. The limit is 53 not ${LENGTH_RELEASE_NAME}. Bye bye!${NC}" && exit 1
    SendSlackMessage "❌ Kubernetes Deploy - Error Deploy in Develop - Number of characters exceeded ❌" "*Namespace*: ${NAMESPACE}\n*Release*: ${RELEASE_NAME}\n*Image:* ${IMAGE}\n*File*: ${FILE}"
  fi
}

function DeployFeature() {
  IMAGE=${CI_REGISTRY_IMAGE}:${CI_COMMIT_REF_SLUG}-${CI_COMMIT_SHORT_SHA}
  HELM_CHART_DIR="/root/charts/deploy-feature"
  if [ ! "${FILE}" ] && [ "${FILE}" == "" ]; then FILE="/root/charts/deploy-feature/values.yaml"; fi
  Status "Context - Feature Branch"
  Status "Image Name Feature: ${IMAGE}"
  Status "Helm Chart DIR Feature: ${HELM_CHART_DIR}"
  Status "Values File Feature: ${FILE}"
  if [ ${LENGTH_RELEASE_NAME} -le 53 ]; then
    NORMALIZE_RELEASE_NAME_FEATURE=${RELEASE_NAME}
    Status "Release Name Feature: ${NORMALIZE_RELEASE_NAME_FEATURE}"
    Status "Helm Upgrade-Install Feature"
    HelmUpgradeInstall ${NORMALIZE_RELEASE_NAME_FEATURE}
  else
    Status "We will try to normalize the Helm Release Name"
    FindFeatureIndex
    CUT_START_FEATURE_RELEASE_NAME=$(echo ${RELEASE_NAME} | cut -f ${CUT_START}-${CUT_END} -d "-")
    CUT_END_FEATURE_RELEASE_NAME=$(echo ${RELEASE_NAME} | cut -f $(expr 1 + ${CUT_END})-${INDEX} -d "-")
    Status "Cut Start Feature Release Name: ${CUT_START_FEATURE_RELEASE_NAME}"
    Status "Cut End Feature Release Name: ${CUT_END_FEATURE_RELEASE_NAME}"
    LENGTH_CUT_START_FEATURE_RELEASE_NAME=$(echo -n "${CUT_START_FEATURE_RELEASE_NAME}" | wc -m)
    LENGTH_CUT_END_FEATURE_RELEASE_NAME=$(echo -n "${CUT_END_FEATURE_RELEASE_NAME}" | wc -m)
    Status "Length Cut Start Feature Release Name: ${LENGTH_CUT_START_FEATURE_RELEASE_NAME}"
    Status "Length Cut End Feature Release Name: ${LENGTH_CUT_END_FEATURE_RELEASE_NAME}"
    END=$(expr 53 - ${LENGTH_CUT_START_FEATURE_RELEASE_NAME} - 1)
    Status "End result: ${END}"
    VALUE_RANDOM=$(echo "${CUT_END_FEATURE_RELEASE_NAME}" | sha256sum | cut -c -${END})
    echo "Random Value: ${VALUE_RANDOM}"
    NORMALIZE_RELEASE_NAME_FEATURE=${CUT_START_FEATURE_RELEASE_NAME}-${VALUE_RANDOM}
    Status "Normalize Release Name Feature: ${NORMALIZE_RELEASE_NAME_FEATURE}"
    Status "Helm Upgrade-Install Feature"
    HelmUpgradeInstall ${NORMALIZE_RELEASE_NAME_FEATURE}
  fi
}

# ==============================================================================
# OPTIONS
# ==============================================================================

while [[ $# > 0 ]]; do
  CMD=${1}
  case $CMD in
    "n"|"-n"|"namespace"|"--namespace")
      NAMESPACE=$(echo ${2} && ${NAMESPACE} || "")
      shift ;;
    "-slack-channel"|"slack-channel"|"--slack-channel")
      SLACK_CHANNEL=$(echo ${2} && ${SLACK_CHANNEL} || "#deploy")
      if [ $SLACK_CHANNEL =~ "#" ]; then
        echo -e "\nSlack Channel is Okay!"
      else
        echo -e "\nAdding # in Slack Channel"
        SLACK_CHANNEL="#${SLACK_CHANNEL}"
      fi
      shift ;;
    "-slack-token"|"slack-token"|"--slack-token")
      SLACK_CLI_TOKEN=$(echo ${2} && ${SLACK_CLI_TOKEN} || "")
      shift ;;
    "help"|"-h"|"h"|"--help")
      Help && exit 1 ;;
    *)
      echo "${RED}ERROR: Unrecognized argument: ${CMD}${NC}"
      Help && exit 1 ;;
  esac
  shift
done

# ==============================================================================
# MAIN
# ==============================================================================

Welcome && AssertIsInstalled "figlet" && AssertIsInstalled "helm" && \
  AssertIsInstalled "kubectl" && CheckGeneralVariables

SendSlackMessage "⚠️ Kubernetes Deploy - A new deploy has started ⚠️" "*Namespace*: ${NAMESPACE}\n*Release*: ${RELEASE_NAME}\n*Image:* ${IMAGE}\n*File*: ${FILE}"

Status "Namespace Name: ${NAMESPACE}"
Status "Release Name: ${RELEASE_NAME}"
Status "Length Release Name: ${LENGTH_RELEASE_NAME} characters"

case ${CURRENT_BRANCH} in
  "develop")
    DeployDevelop
    ;;
  "feature")
    DeployFeature
    ;;
  *)
    Status "Unknown Branch in Auto-Deploy ${CURRENT_BRANCH}."
    exit 1 ;;
esac

Status "${BLUE}Getting Ingress${NC}"
kubectl get ingress -n ${NAMESPACE} | awk {'print $2'}

Status "${BLUE}Getting Pods${NC}"
kubectl get po -n ${NAMESPACE}

SendSlackMessage "✔️ Kubernetes Deploy - Deploy was successfully completed ✔️" "*Namespace*: ${NAMESPACE}\n*Release*: ${RELEASE_NAME}\n*Image:* ${IMAGE}\n*File*: ${FILE}"
