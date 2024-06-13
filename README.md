This repository provides a script that checks out an ActiveState project and copies the artifacts in a
specific cache directory.

The cache directory is /home/hadoop/environment/runtime which is a place where
the runtime will be un-packed on the EMR images later. (Refer to [1] to see how
this should look like without the State Tool)

As the runtime will be executed by potentially hundreds of hosts in parallel
and thousands of time on each host, we do not want to use executors!
Instead we want to use the binaries directly, as this is an undocumented
use-case that we actually want to hide, I wrote this silly script.

It writes a tarball with the artifacts in the `/output` directory along with a file called HASH.
The Path to the python executable can then be set as:

/home/hadoop/environment/runtime/$(cat hash)/usr/bin/python

How to use this script inside your project:

Create a directory `bin` in your project workspace and copy the script file in it:

```sh
mkdir -p bin
curl https://raw.githubusercontent.com/ActiveState/aws-emr-spark-env/main/bin/create_spark_state_env.sh -O bin/create_spark_state_env.sh
```

Now you can create a `spark_env.tar.gz` file:

```sh
PROJECT=myorg/myproject

state auth
ACTIVESTATE_API_KEY=$(state export new-api-key state_env_key)
docker run -it -v $PWD/bin:/output --entrypoint=/bin/bash amazonlinux:2 /output /create_spark_state_env.sh $ACTIVESTATE_API_KEY $PROJECT
```


