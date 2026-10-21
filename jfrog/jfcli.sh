#!/bin/bash
clear
buildType=${1:-"NPM"}

export JF_NAME="psazuse" JF_EDGE_NAME="psazeuwedge" JFROG_CLI_LOG_LEVEL="DEBUG" 
export JF_RT_URL="https://${JF_NAME}.jfrog.io" 
export PROJECT_KEY="npmapptrust" APPLICATION_KEY="swaggerapp" RT_REPO_NPM_VIRTUAL="npmapptrust-virtual" RT_REPO_DOCKER_VIRTUAL="npmapptrust-docker-virtual" 


export TIMESTAMP="$(date '+%Y.%m.%d+%H%M')" 
export BUILD_ID="${TIMESTAMP}" APPLICATION_VERSION="${TIMESTAMP}"
export EVD_KEY_PRIVATE="$(cat ~/.ssh/jfrog_evd_private.pem)" EVD_KEY_PUBLIC="$(cat ~/.ssh/jfrog_evd_public.pem)" EVD_KEY_ALIAS="KRISHNAM_JFROG_EVD_PUBLICKEY"

jf config use ${JF_NAME}

npm-package(){
    rm -rf package-lock.json
    export BUILD_NAME="sh-npm"
    jf npmc --repo-resolve ${RT_REPO_NPM_VIRTUAL} --repo-deploy ${RT_REPO_NPM_VIRTUAL} 
    jf npm cache clean --force
    # Package & BuildPublish
    jf npm install --build-name=${BUILD_NAME} --build-number=${BUILD_ID} --project="${PROJECT_KEY}" --detailed-summary
    jf npm publish --build-name=${BUILD_NAME} --build-number=${BUILD_ID} --project="${PROJECT_KEY}" --detailed-summary
    jf rt bp ${BUILD_NAME} ${BUILD_ID} --collect-git-info=true --collect-env=true --project="${PROJECT_KEY}" --detailed-summary

    # AppTrust
   printf "\n*** AppTrust: App Version create **\n"
   export AT_APP_SPEC_JSON="./jfcli-app-spec.json"
   cat > "${AT_APP_SPEC_JSON}" <<EOF
   {
      "builds": [
        {
          "name": "${BUILD_NAME}",
          "number": "${BUILD_ID}",
          "repository_key": "${PROJECT_KEY}-build-info",
          "include_dependencies": false
        }
      ]
   }
EOF

    printf "AppTrust app spec file content: ${AT_APP_SPEC_JSON}"
    cat ${AT_APP_SPEC_JSON}

    # ref: https://docs.jfrog.com/governance/docs/create-application-version-cli 
    # jf apptrust version-create "app-spring-petclinic" 2026.07.23-1225 --spec="./at-app-spec.json" 
    jf apptrust version-create ${APPLICATION_KEY} ${APPLICATION_VERSION} --spec="${AT_APP_SPEC_JSON}" 
    # jf apptrust version-create ${APPLICATION_KEY} ${APPLICATION_VERSION} --source-type-builds="name=${BUILD_NAME}, id=${BUILD_ID}, repository_key" --tag="prototype" --dry-run
    rm -rf ${AT_APP_SPEC_JSON}

}
docker-package(){
    export BUILD_NAME="docker"
    jf npmc --repo-resolve ${RT_REPO_NPM_VIRTUAL} --repo-deploy ${RT_REPO_NPM_VIRTUAL} 
    jf npm cache clean --force

}



arg_len=${#buildType}
buildType=$(printf "${buildType}" | tr '[:lower:]' '[:upper:]' | xargs)
printf "User Action: ${buildType}, and arg length: ${arg_len}"

case ${buildType} in
    DEFAULT | NPM | NODE | JS)
      npm-package
      ;;
    DOCKER | DKR | DOC)
      docker-package 
      ;;
    *)
      printf "Invalid argument: ${buildType}"
      exit 1
      ;;
esac
printf "\n ----------------------------------------------------------------  "
printf "\n***** [END] TS: $(date +"%Y-%m-%d %H:%M:%S") \n\n"