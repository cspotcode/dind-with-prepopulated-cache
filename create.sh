#!/usr/bin/env bash
set -euxo pipefail

# NOTE: bugs in this script may exist; it was cleaned up to make it generic for
# public sharing, and was not tested after cleanup.
# This may have introduced syntax errors.

# Basic idea:
# Launch a docker engine via docker-in-docker
# Pull images into it
# Save the results as a new image
#
# Tricks:
# Off-the-shelf docker-in-docker declares /var/run/docker as a VOLUME
# We need to avoid this until *after* we've populated the cache
# Thus we do some tricks to switch to /var/run/docker2
# There's probably a cleaner way to do this.

################
#
# CONFIGURATION
#

# Login to an ECR registry, to pull private images into the cache.  Assumes you have a locally-installed AWS CLI with
# credentials.  If you don't need this, remove the relevant bits from this script.
ecrAccountId="<AWS ecr account id here>"
ecrRegion="us-east-1"
ecrRegistry="${ecrAccountId}.dkr.ecr.${ecrRegion}.amazonaws.com"

# Array of images to pull into the cache.  These are just examples
dockerImages=(
    ubuntu/ubuntu:latest
    python
    "$ecrRegistry/some/private/image/your/team/uses:tag"
)

# Tag and push the created image
tag="$ecrRegistry/wherever/your/team/wants/to/store/the/image:latest"

################

# Create network between docker engine and client
network_id="dind-network-$RANDOM"
docker network create "$network_id"

# Create patched dind container
docker build -t dind-with-patched-dockerd-dir -f ./Dockerfile-1 .

# Boot container, running docker engine
container_id="$(
    docker run \
        --network "$network_id" --network-alias docker --privileged \
        -d \
        -e DOCKER_TLS_CERTDIR=/tmp/mnt/docker-certs \
        -v "$PWD/mnt:/tmp/mnt" \
        dind-with-patched-dockerd-dir
)"

# Wait for engine to start; may be unnecessary
sleep 10

command='
echo "$DOCKER_CREDS" | docker login --username AWS --password-stdin '"$ecrRegistry"'
'
for image in "${dockerImages[@]}" ; do
    command="${command} && docker pull $image"
done
# Populate container's cache
# Run the docker client in a different container, connected to the engine we already launched
docker run \
    --rm \
    --network "$network_id" \
    -v "$PWD/mnt:/tmp/mnt:ro" \
    -e DOCKER_TLS_CERTDIR="/tmp/mnt/docker-certs" \
    -e DOCKER_CREDS="$(aws ecr get-login-password --region "$ecrRegion")" \
    docker:latest \
    sh -c "$command"

# Stop the dind engine, save it as an image, teardown containers and network
docker kill "$container_id"
docker commit "$container_id" dind-with-cache-without-volume
docker rm "$container_id"
docker network rm "$network_id"

# Modify the image so that the cache is a docker volume
docker build -t dind-with-cache -f ./Dockerfile-2 .

# 
docker tag dind-with-cache "$tag"
docker push "$tag"