#!/bin/bash
OS="centos:7 centos:8 ubuntu:16.04 ubuntu:18.04 ubuntu:20.04 debian:stretch debian:buster debian:bullseye"
if [[ "${DRY_RUN}" == "true" ]]; then
    OS="ubuntu:18.04"
fi

if [[ -n "${SUDO}" ]]; then
    DOCKER='sudo docker'
else
    DOCKER='docker'
fi

docker_build() {
    NAME="$(sed 's/://g;s/\.//g' <<< ${1})"
    echo "Building for ${NAME}"
    $DOCKER pull civilus/gographite-build-${i}

    $DOCKER create --name ${NAME} civilus/gographite-build-${1}
    $DOCKER start ${NAME}
    if [[ ${LOCAL} != "true" ]]; then
        $DOCKER cp /home/travis/gopath/src ${NAME}:/root/go/src
    else
        $DOCKER cp /root/go/src ${NAME}:/root/go/src
    fi
    $DOCKER exec ${NAME} '/bin/bash' '-x' '/root/pack.sh' "${2}" || return 1
    mkdir -p _pkg
    $DOCKER cp ${NAME}:/root/pkg ./_pkg/ || return 1
    $DOCKER stop ${NAME}
    $DOCKER rm ${NAME}
}

die() {
    echo ${1}
    exit 1
}

if [[ ! "${BUILD_PACKAGES}" == "true" ]]; then
    echo "BUILD_PACKAGES != true"
    exit 0
fi

if [[ -z "${PACKAGECLOUD_TOKEN}" ]]; then
    echo "PACKAGECLOUD_TOKEN not given"
    exit 0
fi

echo "Cleaning up old docker containers (if any)"
for i in $(docker ps -a | awk '{print $1}' | grep -v CONT); do docker rm -f ${i}; done

mkdir -p _pkg/
for i in ${OS}; do
    docker_build ${i} ${1} &
done

gem install package_cloud
wait
pushd _pkg/pkg || die "Failed to 'pushd _pkg/pkg'"
ls

for d in el debian ubuntu; do
    pushd ${d} || die "Failed to pushd to ${d}"
    echo "d=${d}"
    ls

    for v in $(ls); do
        echo "  v=${v}"
        pushd ${v} || die "Failed to pushd to ${v}"
        ls

        for r in $(ls); do
            echo "  r=${r}"
            ls ./${r}/* | grep -q "\(deb\|rpm\)"
            dont_have_pkgs=$?

            if [[ ! -d "${r}" ]] || [[ ${dont_have_pkgs} -ne 0 ]]; then
                continue
            fi

            if [[ "${DRY_RUN}" == "true" ]]; then
                echo "dry_run enabled, won't push anything"
            else
                echo "Will push to 'go-graphite/${r}/${d}/${v}'"
                package_cloud push go-graphite/${r}/${d}/${v} ./${r}/*
            fi
        done

        echo "  popd from v=${v}"
        popd
    done

    echo "popd from d=${d}"
    popd
done

echo "  popd from _pkg/pkg"
popd

echo "Cleaning up docker containers that we've used"
for i in $(docker ps -a | awk '{print $1}' | grep -v CONT); do docker rm -f ${i}; done
