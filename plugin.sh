#!/busybox/sh

set -euo pipefail

export PATH=$PATH:/kaniko/

REGISTRY=${PLUGIN_REGISTRY:-index.docker.io}

if [ "${PLUGIN_USERNAME:-}" ] || [ "${PLUGIN_PASSWORD:-}" ]; then
    DOCKER_AUTH=`echo -n "${PLUGIN_USERNAME}:${PLUGIN_PASSWORD}" | base64 | tr -d "\n"`

    cat > /kaniko/.docker/config.json <<DOCKERJSON
{
    "auths": {
        "${REGISTRY}": {
            "auth": "${DOCKER_AUTH}"
        }
    }
}
DOCKERJSON
fi

if [ "${PLUGIN_JSON_KEY:-}" ];then
    echo "${PLUGIN_JSON_KEY}" > /kaniko/gcr.json
    export GOOGLE_APPLICATION_CREDENTIALS=/kaniko/gcr.json
fi

DOCKERFILE=${PLUGIN_DOCKERFILE:-Dockerfile}
CONTEXT=${PLUGIN_CONTEXT:-$PWD}
LOG=${PLUGIN_LOG:-info}
EXTRA_OPTS=""

if [[ -n "${PLUGIN_TARGET:-}" ]]; then
    TARGET="--target=${PLUGIN_TARGET}"
fi

if [[ "${PLUGIN_SKIP_TLS_VERIFY:-}" == "true" ]]; then
    EXTRA_OPTS="--skip-tls-verify=true"
fi

if [[ "${PLUGIN_CACHE:-}" == "true" ]]; then
    CACHE="--cache=true"
fi

if [ -n "${PLUGIN_CACHE_REPO:-}" ]; then
    CACHE_REPO="--cache-repo=${REGISTRY}/${PLUGIN_CACHE_REPO}"
fi

if [ -n "${PLUGIN_CACHE_TTL:-}" ]; then
    CACHE_TTL="--cache-ttl=${PLUGIN_CACHE_TTL}"
fi

if [ -n "${PLUGIN_MIRROR:-}" ]; then
    REGISTRY_MIRROR="--registry-mirror=${PLUGIN_MIRROR}"
fi

if [[ "${PLUGIN_NOPUSH:-}" == "true" ]]; then
    NOPUSH="--no-push"
fi

if [ -n "${PLUGIN_TARPATH:-}" ]; then
    TARPATH="--tarPath=${PLUGIN_TARPATH}"
fi

BUILD_ARGS_PROXY=$(echo "HTTP_PROXY,HTTPS_PROXY,FTP_PROXY,NO_PROXY,http_proxy,https_proxy,ftp_proxy,no_proxy" | tr ',' '\n' | while read build_arg; do [[ -n "$(eval "echo \${$build_arg:-}")" ]] && echo "--build-arg ${build_arg}=$(eval "echo \$$build_arg")"; done)

if [ -n "${PLUGIN_BUILD_ARGS:-}" ]; then
    BUILD_ARGS=$(echo "${PLUGIN_BUILD_ARGS}" | tr ',' '\n' | while read build_arg; do echo "--build-arg=${build_arg}"; done)
fi

if [ -n "${PLUGIN_BUILD_ARGS_FROM_ENV:-}" ]; then
    BUILD_ARGS_FROM_ENV=$(echo "${PLUGIN_BUILD_ARGS_FROM_ENV}" | tr ',' '\n' | while read build_arg; do echo "--build-arg ${build_arg}=$(eval "echo \$$build_arg")"; done)
fi

# auto_tag, if set auto_tag: true, auto generate .tags file
# support format Major.Minor.Release or start with `v`
# docker tags: Major, Major.Minor, Major.Minor.Release and latest
if [[ "${PLUGIN_AUTO_TAG:-}" == "true" ]]; then
    TAG="${DRONE_TAG:-}"

    echo -n "latest" > .tags
    if [ -n "${TAG:-}" ]; then
        while true; do
	    echo -n ",${TAG}" >> .tags
	    V=${TAG%.*}
	    [ ${V%.*} = ${TAG} ] && break
	    TAG=${V}
        done
    fi
    echo "" >> .tags
fi

if [ -n "${PLUGIN_TAGS:-}" ]; then
    DESTINATIONS=$(echo "${PLUGIN_TAGS}" | tr ',' '\n' | while read tag; do echo "--destination=${REGISTRY}/${PLUGIN_REPO}:${tag} "; done)
elif [ -f .tags ]; then
    DESTINATIONS=$(cat .tags| tr ',' '\n' | while read tag; do echo "--destination=${REGISTRY}/${PLUGIN_REPO}:${tag} "; done)
elif [ -n "${PLUGIN_REPO:-}" ]; then
    DESTINATIONS="--destination=${REGISTRY}/${PLUGIN_REPO}:latest"
else
    DESTINATIONS=""
    NOPUSH="--no-push"
    TARPATH=""
    # Cache is not valid with --no-push
    CACHE=""
fi

/kaniko/executor -v ${LOG} \
    --context=${CONTEXT} \
    --dockerfile=${DOCKERFILE} \
    ${EXTRA_OPTS} \
    ${DESTINATIONS} \
    ${NOPUSH:-} \
    ${CACHE:-} \
    ${CACHE_TTL:-} \
    ${CACHE_REPO:-} \
    ${REGISTRY_MIRROR:-} \
    ${TARPATH:-} \
    ${TARGET:-} \
    ${BUILD_ARGS_PROXY:-} \
    ${BUILD_ARGS:-} \
    ${BUILD_ARGS_FROM_ENV:-}
