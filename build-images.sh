#!/bin/bash

# Terminate on error
set -e

# Prepare variables for later user
images=()
# The image willbe pushed to GitHub image registry under nethserver organization
repobase="ghcr.io/nethserver"
# Configure the image name
reponame="mariadb"

# Create a new empty container image
container=$(buildah from scratch)

# Reuse existing nodebuilder-mariadb container, to speed up builds
if ! buildah containers --format "{{.ContainerName}}" | grep -q nodebuilder-mariadb; then
    echo "Pulling NodeJS runtime..."
    buildah from --name nodebuilder-mariadb -v "${PWD}:/usr/src/mariadb:Z" docker.io/library/node:18-slim
fi

echo "Build static UI files with node..."
buildah run --env="NODE_OPTIONS=--openssl-legacy-provider" nodebuilder-mariadb sh -c "cd /usr/src/mariadb/ui       && yarn install && yarn build"

# Add imageroot directory to the container image
buildah add "${container}" imageroot /imageroot
buildah add "${container}" ui/dist /ui
# Setup the entrypoint, ask to reserve one TCP port with the label and set a rootless container
buildah config --entrypoint=/ \
    --label="org.nethserver.tcp-ports-demand=2" \
    --label="org.nethserver.rootfull=0" \
    --label="org.nethserver.authorizations=traefik@node:routeadm" \
    --label="org.nethserver.images=docker.io/mariadb:10.7.3 docker.io/phpmyadmin/phpmyadmin:5.1.3" \
    "${container}"
# Commit everything
buildah commit "${container}" "${repobase}/${reponame}"

images+=("${repobase}/${reponame}")

#
# NOTICE:
#
# It is possible to build and publish multiple images.
#
# 1. create another buildah container
# 2. add things to it and commit it
# 3. append the image url to the images array
#

#
# Setup CI when pushing to Github. 
# Warning! docker::// protocol expects lowercase letters (,,)
if [[ -n "${CI}" ]]; then
    # Set output value for Github Actions
    printf "::set-output name=images::%s\n" "${images[*],,}"
else
    # Just print info for manual push
    printf "Publish the images with:\n\n"
    for image in "${images[@],,}"; do printf "  buildah push %s docker://%s:%s\n" "${image}" "${image}" "${IMAGETAG:-latest}" ; done
    printf "\n"
fi
