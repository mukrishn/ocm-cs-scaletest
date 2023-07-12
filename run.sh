#!/usr/bin/env bash
set -x

source ./env.sh

_log(){
    if [ $LOG_LEVEL == "debug" ]; then
        echo "DEBUG: $1"
    fi
}

_check_cluster_status(){
    ITR=0
    _log "checking ${CLUSTER_PREFIX}-$job"
    while [ ${ITR} -le 30 ] ; do
        CLUSTER_STATUS=$(ocm list clusters --no-headers --columns state ${CLUSTER_PREFIX}-$job)
        if [ ${CLUSTER_STATUS} == "ready" ] ; then
            _log "${CLUSTER_PREFIX}-$job is ready"
            return 0
        elif [ ${CLUSTER_STATUS} == "installing" ] ; then
            ITR=$((${ITR}+1))
            sleep 10
        else
            _log "cluster state is $CLUSTER_STATUS"
            sleep 10
        fi
    done
    exit 0  
}

_validate_quota(){
    if [ $(($3-$2)) -eq $ITERATIONS ] ; then
        echo "============================================================================="
        echo "GREEN: Consumed quota $(($3-$2)) matches total requested cluster $ITERATIONS "
        echo "============================================================================="
    else
        echo "================================================================================="
        echo "RED: consumed quota $(($3-$2)) does not match total requested cluster $ITERATIONS"
        echo "================================================================================="
    fi
}

_create_cluster(){
    i_count=$(_check_ocm_quota cluster)
    for job in $(seq 1 $ITERATIONS);
    do
        _log "Creating ${CLUSTER_PREFIX}-$job"
        envsubst < ./cluster_payload.json > cluster_payload_$job.json
        ocm post /api/clusters_mgmt/v1/clusters --body cluster_payload_$job.json
    done

    for job in $(seq 1 $ITERATIONS);
    do
        _log "Checking ${CLUSTER_PREFIX}-$job"
        _check_cluster_status
    done
    f_count=$(_check_ocm_quota cluster)
    _validate_quota cluster $i_count $f_count
}

_delete_cluster(){
        echo "================================================================================="

}

_churn_cluster(){
        echo "================================================================================="

}

_create_machinepool(){
        echo "================================================================================="

}

_delete_machinepool(){
        echo "================================================================================="

}

_scale_machinepool(){
        echo "================================================================================="

}

_churn_machinepool(){
        echo "================================================================================="

}

_check_ocm_quota(){
    if [ $1 == "cluster" ] ; then
        consumed=$(ocm get /api/accounts_mgmt/v1/organizations/$ORG_ID/quota_cost -p search="quota_id='cluster|byoc|osd'" | jq -r '.items[].consumed')
    elif [ $1 == "nodes" ] ; then
        cpu=$(ocm get /api/accounts_mgmt/v1/organizations/$ORG_ID/quota_cost -p search="quota_id='compute.node|cpu|byoc|osd'" | jq -r '.items[].consumed')
        consumed=$cpu/$cpu_per_node
    elif [ $1 == "cpu" ] ; then
        consumed=$(ocm get /api/accounts_mgmt/v1/organizations/$ORG_ID/quota_cost -p search="quota_id='compute.node|cpu|byoc|osd'" | jq -r '.items[].consumed')
    else
        _log "Unknown option"
        exit 1
    fi
    return $consumed
}


setup(){

    _log "Install required CLIs"
    check_cli=$(ocm version)
    if [[ $? -ne 0 ]]; then
        _log "Install OCM CLI"
        OCM_CLI_FORK="https://github.com/openshift-online/ocm-cli"
        git clone -q --depth=1 --single-branch --branch ${OCM_CLI_VERSION} ${OCM_CLI_FORK}
        pushd ocm-cli
        sudo PATH=$PATH:/usr/bin:/usr/local/go/bin make
        sudo mv ocm /usr/local/bin/
        popd
    fi
    check_cli=$(rosa version)   
    if [[ $? -ne 0 ]]; then
        _log "Install AWS CLI"
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        ./aws/install

        _log "Install ROSA CLI"
        ROSA_CLI_FORK=https://github.com/openshift/rosa
        git clone -q --depth=1 --single-branch --branch ${ROSA_CLI_VERSION} ${ROSA_CLI_FORK}
        pushd rosa
        make
        sudo mv rosa /usr/local/bin/
        rosa download openshift-client
        tar xzvf openshift-client-linux.tar.gz
        mv oc kubectl /usr/local/bin/
        popd
    fi

    echo "OCM perf test.."
    _log "Clean-up existing OSD access keys.."
    AWS_KEY=$(aws iam list-access-keys --user-name OsdCcsAdmin --output text --query 'AccessKeyMetadata[*].AccessKeyId')
    LEN_AWS_KEY=`echo $AWS_KEY | wc -w`
    if [[  ${LEN_AWS_KEY} -eq 2 ]]; then
        aws iam delete-access-key --user-name OsdCcsAdmin --access-key-id `printf ${AWS_KEY[0]}`
    fi
    _log "Create new OSD access key.."
    export ADMIN_KEY=$(aws iam create-access-key --user-name OsdCcsAdmin)
    export AWS_ACCESS_KEY_ID=$(echo $ADMIN_KEY | jq -r '.AccessKey.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo $ADMIN_KEY | jq -r '.AccessKey.SecretAccessKey')

    sleep 60 # it takes a few sec for new access key
    _log "Check AWS Username..."
    aws iam get-user | jq -r .User.UserName

    ocm login --url=https://api.stage.openshift.com --token="${TOKEN}"
    ocm whoami
    export ORG_ID=$(ocm whoami | jq -r '.organization.id')
    rosa login --env=${ENVIRONMENT}
    export LOG_LEVEL=${LOG_LEVEL:-"debug"}
}


case ${WORKLOAD} in
  cluster)
    export ITERATIONS=${ITERATIONS:-100}
    _create_cluster
    _delete_cluster
    _churn_cluster
  ;;
  machinepool)
    _create_machinepool
    _delete_machinepool
    _scale_machinepool
    _churn_machinepool
  ;;
  *)
     log "Unknown load ${WORKLOAD}, exiting"
     exit 1
  ;;
esac

