#!/bin/bash
clear
buildType=${1:-"DKR"} # ${1:-"NPM"}

export JF_NAME="psazuse" JF_EDGE_NAME="psazeuwedge" JFROG_CLI_LOG_LEVEL="DEBUG" 
export JF_RT_URL="https://${JF_NAME}.jfrog.io" 
export PROJECT_KEY="npmapptrust" APPLICATION_KEY="swaggerapp" RT_REPO_NPM_VIRTUAL="npmapptrust-virtual" RT_REPO_DOCKER_VIRTUAL="npmapptrust-docker-virtual" 
export DOCKER_USER="${PSAZUSE_JF_USERNAME}" DOCKER_PWD="${PSAZUSE_JF_ACCESS_TOKEN}"


export TIMESTAMP="$(date '+%Y.%m.%d+%H%M')" TODAYS_DATE="$(date '+%Y-%m-%d')"
export BUILD_ID="$(date '+%Y.%m.%d%H%M')" APPLICATION_VERSION="${TIMESTAMP}"
export EVD_KEY_PRIVATE="$(cat ~/.ssh/jfrog_evd_private.pem)" EVD_KEY_PUBLIC="$(cat ~/.ssh/jfrog_evd_public.pem)" EVD_KEY_ALIAS="KRISHNAM_JFROG_EVD_PUBLICKEY"

jf config use ${JF_NAME}
rm -rf package-lock.json .npmrc

npm-package(){
    export BUILD_NAME="sh-npm"
    jf npmc --repo-resolve ${RT_REPO_NPM_VIRTUAL} --repo-deploy ${RT_REPO_NPM_VIRTUAL} 
    # jf npm cache clean --force
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
    if [[ -z "${DOCKER_USER:-}" || -z "${DOCKER_PWD:-}" ]]; then
        printf "\nMissing PSAZUSE_JF_USERNAME or PSAZUSE_JF_ACCESS_TOKEN\n" >&2
        exit 1
    fi
    set -euo pipefail

    export BUILD_NAME="sh-dkr" JF_DKR_REGISTRY="${JF_NAME}.jfrog.io"
    export DOCKER_FILE="./jfrog/Dockerfile" DOCKER_BUILDX_PLATFORMS="linux/amd64,linux/arm64"
    export DOCKER_METADATA_JSON="build-metadata.json" DOCKER_IMAGE_FILE="docker-image.txt"
    export TAG11="${JF_DKR_REGISTRY}/${RT_REPO_DOCKER_VIRTUAL}/${BUILD_NAME}:${BUILD_ID}"
    export TAG12="${JF_DKR_REGISTRY}/${RT_REPO_DOCKER_VIRTUAL}/${BUILD_NAME}:latest"
    export TAG13="${JF_DKR_REGISTRY}/${RT_REPO_DOCKER_VIRTUAL}/${BUILD_NAME}:${TODAYS_DATE}"
    jf npmc --repo-resolve "${RT_REPO_NPM_VIRTUAL}" --repo-deploy "${RT_REPO_NPM_VIRTUAL}"
    # jf npm cache clean --force
    jf npm install
    jf npm run build

    # Docker login. Password stays on stdin so it is not printed or passed as an argument.
    printf "\nDocker login user: %s\n" "${DOCKER_USER}"
    printf '%s\n' "${DOCKER_PWD}" | docker login "${JF_DKR_REGISTRY}" --username "${DOCKER_USER}" --password-stdin

    # The default Rancher Desktop driver cannot push a multi-arch manifest.
    if ! docker buildx inspect jf-dkr >/dev/null 2>&1; then
        docker buildx create --name jf-dkr --driver docker-container --use
    else
        docker buildx use jf-dkr
    fi
    docker buildx inspect jf-dkr --bootstrap >/dev/null

    docker buildx build \
        -f "${DOCKER_FILE}" \
        --platform "${DOCKER_BUILDX_PLATFORMS}" \
        --provenance=false \
        --metadata-file "${DOCKER_METADATA_JSON}" \
        --push \
        -t "${TAG11}" \
        -t "${TAG12}" \
        -t "${TAG13}" \
        .

    image_digest="$(jq -er '.["containerimage.digest"]' "${DOCKER_METADATA_JSON}")"
    case "${image_digest}" in
        sha256:*) ;;
        *)
            printf "\nDocker metadata is missing a sha256 digest: %s\n" "${image_digest}" >&2
            exit 1
            ;;
    esac
    printf "DOCKER_IMAGE_DIGEST: %s\n" "${image_digest}"
    # jf rt bdc requires exactly one line: <image-tag>@sha256:<manifest-digest>
    printf '%s@%s\n' "${TAG11}" "${image_digest}" | tee "${DOCKER_IMAGE_FILE}"

    # Build Publish. bdc records the image already pushed by buildx; bp publishes that build-info.
    jf rt bdc "${RT_REPO_DOCKER_VIRTUAL}" --image-file "${DOCKER_IMAGE_FILE}" --build-name="${BUILD_NAME}" --build-number="${BUILD_ID}" --project="${PROJECT_KEY}"
    jf rt bp "${BUILD_NAME}" "${BUILD_ID}" --collect-git-info=true --collect-env=true --project="${PROJECT_KEY}" --detailed-summary

    # AppTrust
   printf "\n*** AppTrust: App Version create **\n"
   export AT_APP_SPEC_JSON="./jfcli-app-spec-docker.json"
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

    rm -rf ${AT_APP_SPEC_JSON}


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