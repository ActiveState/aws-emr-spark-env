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


export S3_UPLOAD_PREFIX=s3://your-bucket/your-prefix

# bundle up your own source code (optional)
git archive --format=zip HEAD:src > project_archive.zip

export APP_ID='...'

export EXECUTION_ROLE='...'
export EXECUTION_ROLE_ARN=$(aws iam get-role --role-name $EXECUTION_ROLE | jq -r .Role.Arn )

s3_upload() {
    S3_PATH=$1; shift
    FILE=$1; shift

    BASE_NAME=`basename $FILE`
    S3_URL=$S3_PATH/$BASE_NAME
    aws --profile sso s3 ls $S3_URL && return

    echo "Uploading $FILE to $S3_URL ..."
    aws --profile sso s3 cp $FILE $S3_URL
}

# upload to the s3
s3_upload $S3_UPLOAD_PREFIX bin/state_env.tar.gz
s3_upload $S3_UPLOAD_PREFIX project_archive.zip 
s3_upload $S3_UPLOAD_PREFIX migration-script.py

JOB_DRIVER=$(jq -n \
     --arg cs "$CORES" \
     --arg mem "$MEMORY" \
     --arg execs "$MAX_EXECUTORS" \
     --arg migration_file "$S3_UPLOAD_PATH/migration-script.py" \
     --arg state_env_file "$S3_UPLOAD_PATH/state_env.tar.gz" \
     --arg project_archive_file "$S3_PATH/project_archive.zip" \
     --arg python_path "./environment/runtime/$(cat bin/hash)/usr/bin/python" \
     --argjson args "[$LIMIT_ARGS\"--output_suffix=$SUFFIX\", \"$SOURCE\"]" \
     '{
        sparkSubmit: {
          entryPoint: $migration_file,
          entryPointArguments: $args,
          sparkSubmitParameters: (
            "--conf spark.executor.cores="+$cs+
            " --conf spark.executor.memory="+$mem+
            " --conf spark.driver.cores="+$cs+
            " --conf spark.driver.memory="+$mem+
            " --conf spark.archives="+$state_env_file+"#environment,"+
            " --conf spark.emr-serverless.driverEnv.PYSPARK_DRIVER_PYTHON="+$python_path+
            " --conf spark.emr-serverless.driverEnv.PYSPARK_PYTHON="+$python_path+
            " --conf spark.executorEnv.PYSPARK_PYTHON="+$python_path+ 
            " --conf spark.submit.pyFiles="+$project_archive+
            " --conf spark.dynamicAllocation.maxExecutors="+$execs+
            " --conf spark.hadoop.hive.metastore.client.factory.class=com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory"
            )
        }
      }')

CONFIG_OVERRIDES=$(jq -n \
    --arg log_uri "$S3_PATH/logs" \
    '{
        monitoringConfiguration: {
            s3MonitoringConfiguration: {
                logUri: $log_uri
            }
        }
    }'
)

JOB_ID=$(aws emr-serverless start-job-run --application-id $APP_ID \
   --execution-role-arn $EXECUTION_ROLE_ARN \
   --name $APP_NAME \
   --job-driver "$JOB_DRIVER" \
   --configuration-overrides "$CONFIG_OVERRIDES" | jq -r .jobRunId )

echo $JOB_ID

watch "aws emr-serverless get-job-run --application-id $APP_ID --job-run-id $JOB_ID | jq '.jobRun | {state: .state, details: .stateDetails}'"
```


