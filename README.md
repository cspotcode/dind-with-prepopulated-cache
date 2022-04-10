An experiment to create a docker-in-docker container with a prepopulated cache of
images.

## Quick start

Read and customize `./create.sh`.  Then run it.

## Motivation

Could be used to run docker and docker-compose workloads on CI systems that do
not give access to the host's docker engine, but that *do* cache the
docker-in-docker image.  For these workloads, we ask the CI system to run our
code against a docker-in-docker container.

The off-the-shelf docker-in-docker image starts with an empty cache every time.
With this experiment, you can pre-populate the layer cache with the images used
by your tests, hopefully to speed up your workflows.

## Expectation

Read these carefully; this can be a bit confusing.  This image is only useful given
the following scenario:

- CI does not give access to host's docker engine
- CI *does* run your workloads inside of docker images that you choose
- CI host *does* use its own layer cache when pulling and running the
aforementioned images you choose.

For example, Kubernetes runs containers within pods (collections of containers) on nodes (physical servers).  If a pod tries to launch a
docker-in-docker container, and the node has *already* pulled that docker-in-docker image,
then the container can start faster.  The node's layer cache makes this possible.

## Potential caveats / areas of research

### Volume creation

When booting a docker-in-docker image with pre-populated cache, I'm pretty sure
the cache needs to be copied out of the image into a volume before the container can start.  The
cache cannot exist within the container's overlay / copy-on-write filesystem.

Is this copying operation prohibitively slow?  I'm not sure; needs to be tested.

### Filesystem driver incompatibilities

When I tried to build this image on a local Ubuntu installation, and then run the image
on kubernetes, I got an error saying that the aufs driver was not available.  I assume
this means the docker layer cache was created with aufs on my local Ubuntu machine,
and then the Kubernetes node was not allowed to use the aufs driver.

Does this mean the image will work if its created on Kubernetes?  Ideally, CI would
create the image anyway, so that's a reasonable thing to do.  Or is this likely
to break regardless?
