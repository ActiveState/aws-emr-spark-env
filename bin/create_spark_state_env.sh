#!/bin/bash

# To be upfront:  I'm not a fan of this solution!

# This script checks out the buildgraph project and copies the artifacts in a
# specific runtime directory.

# The runtime directory is /home/hadoop/environment/runtime which is a place
# where the runtime will be un-packed on the EMR images later. (Refer to [1] to
# see how this should look like without the State Tool)

# As the runtime will be executed by potentially hundreds of hosts in parallel
# and thousands of time on each host, we do not want to use executors!
# Instead we want to use the binaries directly.

# It writes a tarball with the runtime artifacts in the `/output` directory.
# The Path to the python executable can then be set as:
#
# /home/hadoop/environment/usr/bin/python

# How to use this script (in your project workspace):
# PROJECT=myorg/myproject
# state auth
# ACTIVESTATE_API_KEY=$(state export new-api-key state_env_key)
# docker run -it -v $PWD/bin:/output --entrypoint=/bin/bash amazonlinux:2 /output /create_spark_state_env.sh $ACTIVESTATE_API_KEY $PROJECT


if [ $# -lt 1 ];
then
	echo "First argument needs to be an API key for State Tool authorization"
	exit 1
fi

API_KEY=$1
PROJECT=${2:-ActiveState/buildgraph}

# This script is run inside an amazonlinux container, so we need to install a couple things
install_deps() {
    yum update -y
    yum install file curl tar gzip -y

    sh <(curl -q https://platform.activestate.com/dl/cli/install.sh) --force -n -t $HOME/bin </dev/null
    source $HOME/.bashrc
}

[ -x /usr/bin/tar ] || install_deps

# Set the cache directory relative to /home/hadoop/environment as advised in [1]
# It might not actually be necessary, because our ActiveState runtimes are fairly re-locatable
mkdir -p /home/hadoop/environment/runtime

# we are checking out the PROJECT in a temporary directory, but are really just
# interested in the artifacts in the cache directory
mkdir -p /tmp/ignore
state auth --token $API_KEY
state checkout $PROJECT /tmp/ignore --runtime-path /home/hadoop/environment/runtime

pushd /home/hadoop/environment; tar czf /output/state_env.tar.gz . ; popd

# [1]: https://docs.aws.amazon.com/emr/latest/EMR-Serverless-UserGuide/using-python.html
