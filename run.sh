#!/usr/bin/env bash

source ./env.sh

_log(){
    if [[ $LOG_LEVEL == "debug" ]]; then
        echo "DEBUG: $1"
    fi
}

_cluster_id(){
    ocm list cluster | grep $1 | awk '{print$1}'
}

_kubeconfig(){
    ocm get /api/clusters_mgmt/v1/clusters/$(_cluster_id $1)/credentials | jq -r .kubeconfig > ./$1
}

_csv(){
    echo $1 >> cs-report.csv
}

_check_cluster_status(){
    ITR=0
    _ID=$(_cluster_id "$1")
    if [[ $_ID != "" ]]; then    
        while [ ${ITR} -le 30 ] ; do
            CLUSTER_STATUS=$(ocm list clusters --no-headers --columns state $_ID | xargs)
            if [[ ${CLUSTER_STATUS} == "ready" ]] ; then
                _log "$1 is ready"
                return 0
            elif [[ ${CLUSTER_STATUS} == "" ]] ; then
                _log "cluster $1 is deleted"
                return 0
            else
                _log "cluster state is $CLUSTER_STATUS"
                ITR=$((${ITR}+1))
                sleep 60
            fi
        done
    else
        _log "cluster $1 is deleted"
        return 0
    fi
    exit 0  
}

_validate_quota(){
    a=$3
    b=$2
    echo "==========================================================================="
    if [[ $1 == "cluster" ]] ; then
        if [[ $((a-b)) -eq $4 ]] ; then
            echo "GREEN: Consumed quota $((a-b)) matches total requested cluster $4 "
            _csv "cluster,$4,$((a-b)),Pass" 
        else
            echo "RED: Consumed quota $((a-b)) does not match total requested cluster $4"
            _csv "cluster,$4,$((a-b)),Fail" 
        fi
    elif [[ $1 == "churn" ]] ; then
        if [[ $a -eq $b ]] ; then
            echo "GREEN: Consumed quota $a matches before and after churn $4 $b"
            _csv "churn-$4,$a,$b,Pass" 
        else
            echo "RED: Consumed quota $a does not match before and after churn $4 $b"
            _csv "churn-$4,$a,$b,Fail" 
        fi
    elif [[ $1 == "mcp" ]] ; then
        NODES=$(( (a-b)/$NUMBER_OF_CPU_OF_INSTANCE_TYPE ))
        if [[ $NODES -eq $4 ]] ; then
            echo "GREEN: Consumed quota $NODES matches total requested MCP nodes $4 "
            _csv "machinepool,$4,$NODES,Pass" 
        else
            echo "RED: Consumed quota $NODES does not match total requested MCP nodes $4"
            _csv "machinepool,$4,$NODES,Fail" 
        fi        
    else
        echo "skipping validation"
    fi
    echo "==========================================================================="   
}

_create_cluster(){
    for job in $(seq 1 $1);
    do
        export JOB=$job
        export CLUSTER_NAME=$2-$job-fake
        _log "Creating ${CLUSTER_NAME}"
        envsubst < ./cluster_payload.json > cluster_payload_$job.json
        ocm post /api/clusters_mgmt/v1/clusters --body cluster_payload_$job.json 2>&1 > /dev/null 
    done
    # pause for a few sec before looking for status
    sleep 10
    for job in $(seq 1 $1);
    do
        export CLUSTER_NAME=$2-$job-fake
        _log "Checking ${CLUSTER_NAME}"
        _check_cluster_status ${CLUSTER_NAME}
    done
}

_delete_cluster(){
    for job in $(seq 1 $1);
    do
        export CLUSTER_NAME=$2-$job-fake
        _log "Deleting ${CLUSTER_NAME}"
         ocm delete cluster "$(_cluster_id ${CLUSTER_NAME})" &
    done

    for job in $(seq 1 $1);
    do
        export CLUSTER_NAME=$2-$job-fake
        _log "Checking ${CLUSTER_NAME}"
        _check_cluster_status ${CLUSTER_NAME}
    done
}

_wait_for_delete(){
    ITR=0
    if [[ $1 == "cluster" ]]; then
        while [ ${ITR} -le 100 ] ; do
            CHECK=$(ocm list cluster | grep $2 | wc -l)
            if [[ $CHECK -eq 0 ]]; then
                _log "All $2 cluster got removed"
                return 0
            else
                _log "Still uninstalling some clusters"
                ITR=$((ITR+1))
                sleep 60
            fi
        done
    else
        while [ ${ITR} -le 100 ] ; do
            CHECK=$(rosa list machinepool -c $3 | grep churn | awk '{print $1}' | wc -l)
            if [[ $CHECK -eq 0 ]]; then
                _log "All extra machinepool got removed from $3"
                return 0
            else
                _log "Still deleting some machinepools"
                ITR=$((ITR+1))
                sleep 60
            fi
        done    
    fi
}

_churn_cluster(){
    i_count=$(_check_ocm_quota cluster)
    for n in $(seq 1 3);
    do
        _create_cluster $1 "churn$n"  # args are 1> number of cluster 2> cluster name prefix
        _delete_cluster $1 "churn$n" & # args are 1> number of cluster 2> cluster name prefix
    done
    _wait_for_delete cluster churn
    f_count=$(_check_ocm_quota cluster)

    _log "Validate Creation.."
    _validate_quota churn $f_count $i_count cluster
}

_get_cluster_info(){
    export A_REGION=$(rosa describe cluster -c $1 | grep Region: | awk '{print$2}' | xargs )
    export O_VERSION=$(rosa describe cluster -c $1 | grep Version: | awk '{print$3}' | xargs)
    export A_ZONE=$(rosa list machinepool -c $1 | grep workers | awk '{print$6}' | head -1) # to pick a single available zone
}

_mcp_status(){
    DESIRED=$(rosa list machinepool -c $1 | grep $2 | awk '{print$3}')
    ITR=0
    while [ ${ITR} -le 10 ] ; do
        CURRENT=$(rosa list machinepool -c $1 | grep $2 | awk '{print$4}')
        if [[ $DESIRED -eq $CURRENT ]]; then
            _log "Machinepool $2 of cluster $1 is matching the desired state"
            return 0
        elif [[ ! $DESIRED -eq $CURRENT ]]; then 
            _log "Still waiting for the nodes, $CURRENT/$DESIRED ready"
            sleep 60
            ITR=$((ITR+1))
        else
            _log "Machinepool $2 of cluster $1 got deleted"
        fi
    done
}

_create_machinepool(){
    if [[ $3 ]]; then
        REPLICA=" --enable-autoscaling --min-replicas ${NUMBER_OF_NODES_PER_MCP} --max-replicas $((NUMBER_OF_NODES_PER_MCP+10)) "
    else
        REPLICA=" --replicas ${NUMBER_OF_NODES_PER_MCP} "
    fi

    for mcp in $(seq 1 $1);
    do
        _log "Create machinepool $2-$mcp-mcp in cluster ${CLUSTER_NAME}"
        rosa create machinepool --cluster "$(_cluster_id ${CLUSTER_NAME})" --name $2-$mcp-mcp --instance-type ${WORKER_TYPE} ${REPLICA} --availability-zone $A_ZONE 2>&1 > /dev/null
    done
    sleep 30
    for mcp in $(seq 1 $1);
    do
        _log "Check machinpool $2-$mcp-mcp in cluster ${CLUSTER_NAME} status"
        _mcp_status ${CLUSTER_NAME} $2-$mcp-mcp 
    done    
}

_delete_machinepool(){
    for mcp in $(seq 1 $1);
    do
        _log "Delete machinepool $2-$mcp-mcp in cluster ${CLUSTER_NAME}"
        rosa delete machinepool --cluster "$(_cluster_id ${CLUSTER_NAME})" $2-$mcp-mcp -y 2>&1 > /dev/null
    done

    for mcp in $(seq 1 $1);
    do
        _log "Check machinpool $2-$mcp-mcp in cluster ${CLUSTER_NAME} status"
        _mcp_status ${CLUSTER_NAME} $2-$mcp-mcp
    done 

}

_scale_machinepool(){
    for mcp in $(seq 1 $1);
    do
        _log "Scale up machinepool $2-$mcp-mcp in cluster ${CLUSTER_NAME}"
        rosa edit machinepool -c "$(_cluster_id ${CLUSTER_NAME})" $2-$mcp-mcp  --replicas $((NUMBER_OF_NODES_PER_MCP+1)) 2>&1 > /dev/null
    done
    for mcp in $(seq 1 $1);
    do
        _log "Check machinpool $2-$mcp-mcp in cluster ${CLUSTER_NAME} status"
        _mcp_status ${CLUSTER_NAME} $2-$mcp-mcp 
    done    
}

_churn_machinepool(){
    i_count=$(_check_ocm_quota cpu)
    for n in $(seq 1 3);
    do
        _create_machinepool $1 "churn$n"  # args are 1> number of mcp 2> mcp name prefix
        _scale_machinepool $1 "churn$n"  # args are 1> number of mcp 2> mcp name prefix
        _delete_machinepool $1 "churn$n" & # args are 1> number of mcp 2> mcp name prefix
    done
    _wait_for_delete machinepool churn ${BASE_CLUSTER}-1  # 3rd argument only for mcp cleanup
    f_count=$(_check_ocm_quota cpu)

    _log "Validate Creation.."
    _validate_quota churn $f_count $i_count machinepool
}

_check_ocm_quota(){
    if [[ $1 == "cluster" ]] ; then
        echo $(ocm get /api/accounts_mgmt/v1/organizations/$ORG_ID/quota_cost -p search="quota_id='cluster|byoc|osd'" | jq -r '.items[].consumed')
    else
        echo $(ocm get /api/accounts_mgmt/v1/organizations/$ORG_ID/quota_cost -p search="quota_id='compute.node|cpu|byoc|moa|marketplace'" | jq -r '.items[].consumed')
    fi
}

_create_upgrade_profile(){
    rosa upgrade cluster -c $1 --mode auto --schedule-date 2023-08-04 --schedule-time 23:30 --control-plane -y 2>&1 > /dev/null
}

_delete_upgrade_profile(){
    rosa delete upgrade cluster -c $1 -y 2>&1 > /dev/null
}

_validate_tc(){
    LIST_ALL=$(rosa list tuning-configs -c $1 -o json | jq -r '.[].name' | xargs)
    TUNED_PROFILE_COUNT=$(oc --kubeconfig ./$1 get tuned -n openshift-cluster-node-tuning-operator | grep ${LIST_ALL// /\\|} | wc -l) 
    echo "==========================================================================="
    if [[  $(echo $LIST_ALL | wc -w) -eq $TUNED_PROFILE_COUNT  ]]; then
        echo "GREEN: Tuned profile $TUNED_PROFILE_COUNT matches total tuning-config $(echo $LIST_ALL | wc -w)"
        _csv "tuning-config,$(echo $LIST_ALL | wc -w),$TUNED_PROFILE_COUNT,Pass" 

    else
        echo "RED: Tuned profile $TUNED_PROFILE_COUNT does not match total tuning-config $(echo $LIST_ALL | wc -w)"
        _csv "tuning-config,$(echo $LIST_ALL | wc -w),$TUNED_PROFILE_COUNT,Fail" 
    fi
    echo "==========================================================================="
}

_create_tuning_config(){
    for key in dirty_ratio dirty_background_ratio overcommit_ratio swappiness;
    do
        export SYSTEM_KEY=$key
        export RATIO=50
        export TUNED_NAME=${key//_/}
        envsubst < ./tuned_config.spec > tuned_config.json
        _log "Create tuning configs $key"
        rosa create tuning-configs --name=tuned${key//_/} --spec-path tuned_config.json -c $1 2>&1 > /dev/null
        _log "Apply tuning-config on a machinepool"
    done
    _update_tuning_config $1
}

_update_tuning_config(){
    for key in dirty_ratio dirty_background_ratio overcommit_ratio swappiness;
    do
        export SYSTEM_KEY=$key
        export RATIO=55
        export TUNED_NAME=${key//_/}
        envsubst < ./tuned_config.spec > tuned_config.json
        _log "Update tuning configs $key"
        rosa update tuning-configs tuned${key//_/} --spec-path tuned_config.json -c $1 2>&1 > /dev/null
    done
    LIST_ALL=$(rosa list tuning-configs -c $1 -o json | jq -r '.[].name' | xargs)
    rosa update machinepool -c $1 workers-0 --tuning-configs ${LIST_ALL// /,}
    sleep 5
    _validate_tc $1
    sleep 30
    _delete_tuning_config $1       
}

_delete_tuning_config(){
    rosa update machinepool -c $1 workers-0 --tuning-configs ""
    for key in dirty_ratio dirty_background_ratio overcommit_ratio swappiness;
    do
        _log "Delete tuning configs $key"
        rosa delete tuning-configs tuned${key//_/} -c $1 -y 2>&1 > /dev/null
    done
    _validate_tc $1    
}

setup(){

    _log "Install required CLIs"
    if [[ ! $(ocm version) ]]; then
        _log "Install OCM CLI"
        OCM_CLI_FORK="https://github.com/openshift-online/ocm-cli"
        git clone -q --depth=1 --single-branch --branch ${OCM_CLI_VERSION} ${OCM_CLI_FORK}
        pushd ocm-cli || exit
        sudo PATH=$PATH:/usr/bin:/usr/local/go/bin make
        sudo mv ocm /usr/local/bin/
        popd || exit
    fi
    if [[ ! $(rosa version) ]]; then
        _log "Install AWS CLI"
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        ./aws/install

        _log "Install ROSA CLI"
        ROSA_CLI_FORK=https://github.com/openshift/rosa
        git clone -q --depth=1 --single-branch --branch ${ROSA_CLI_VERSION} ${ROSA_CLI_FORK}
        pushd rosa || exit
        make
        sudo mv rosa /usr/local/bin/
        rosa download openshift-client
        tar xzvf openshift-client-linux.tar.gz
        mv oc kubectl /usr/local/bin/
        popd || exit
    fi

    echo "OCM perf test kick started.."
    ocm login --url=https://api.stage.openshift.com --token="${TOKEN}"
    export ORG_ID=$(ocm whoami | jq -r '.organization.id')
    rosa login --env=${ENVIRONMENT} 
}

export LOG_LEVEL=${LOG_LEVEL:-"debug"}

echo "testcase,attempted,consumed,status" > cs-report.csv

setup
case ${WORKLOAD} in
  cluster|all)

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
    export ITERATIONS=${ITERATIONS:-100}
    i_count=$(_check_ocm_quota cluster)
    _create_cluster $ITERATIONS "job"  # args are 1> number of cluster 2> cluster name prefix
    f_count=$(_check_ocm_quota cluster)
    _log "Validate Creation.."
    _validate_quota cluster $i_count $f_count $ITERATIONS

    _churn_cluster 25

    i_count=$(_check_ocm_quota cluster)
    _delete_cluster $ITERATIONS "job"  # args are 1> number of cluster 2> cluster name prefix
    f_count=$(_check_ocm_quota cluster)
    _log "Validate Creation.."
    _validate_quota cluster $f_count $i_count $ITERATIONS

  ;;&
  machinepool|all)
    
    for cluster in $(seq 1 $NUMBER_OF_BASE_CLUSTER);
    do
        export CLUSTER_NAME=${BASE_CLUSTER}-$cluster
        _log "Download kubeconfig"
        _kubeconfig $CLUSTER_NAME
        _get_cluster_info $CLUSTER_NAME 
        i_count=$(_check_ocm_quota cpu)
        _create_machinepool $NUMBER_OF_MCP "job" # args are 1> number of mcp 2> mcp name prefix
        f_count=$(_check_ocm_quota cpu)
        _validate_quota mcp $i_count $f_count $((NUMBER_OF_MCP*NUMBER_OF_NODES_PER_MCP))

        _scale_machinepool $NUMBER_OF_MCP "job" # args are 1> number of mcp 2> mcp name prefix
        f_count=$(_check_ocm_quota cpu)
        TOTAL=$((NUMBER_OF_NODES_PER_MCP+1))
        _validate_quota mcp $i_count $f_count $((NUMBER_OF_MCP*TOTAL))

        i_count=$(_check_ocm_quota cpu)
        _delete_machinepool $NUMBER_OF_MCP "job" # args are 1> number of mcp 2> mcp name prefix
        f_count=$(_check_ocm_quota cpu)
        TOTAL=$((NUMBER_OF_NODES_PER_MCP+1))
        _validate_quota mcp $f_count $i_count $((NUMBER_OF_MCP*TOTAL))

        i_count=$(_check_ocm_quota cpu)
        _create_machinepool $NUMBER_OF_MCP "autoscale" "autoscale" # args are 1> number of mcp 2> mcp name prefix
        f_count=$(_check_ocm_quota cpu)
        TOTAL=$((NUMBER_OF_NODES_PER_MCP+10))
        _validate_quota mcp $i_count $f_count $((NUMBER_OF_MCP*TOTAL))

        i_count=$(_check_ocm_quota cpu)
        _delete_machinepool $NUMBER_OF_MCP "autoscale" # args are 1> number of mcp 2> mcp name prefix
        f_count=$(_check_ocm_quota cpu)
        TOTAL=$((NUMBER_OF_NODES_PER_MCP+10))
        _validate_quota mcp $f_count $i_count $((NUMBER_OF_MCP*TOTAL))
    done

    _churn_machinepool 25
  ;;&

  upgrade-policy)
    
    for cluster in $(seq 1 $NUMBER_OF_BASE_CLUSTER);
    do
        export CLUSTER_NAME=${BASE_CLUSTER}-$cluster
        _log "Download kubeconfig"
        _kubeconfig $CLUSTER_NAME
        _get_cluster_info $CLUSTER_NAME 
        _create_upgrade_profile $CLUSTER_NAME
        _delete_upgrade_profile $CLUSTER_NAME
    done
  ;;&

  tuning-config|all)
    
    for cluster in $(seq 1 $NUMBER_OF_BASE_CLUSTER);
    do
        export CLUSTER_NAME=${BASE_CLUSTER}-$cluster
        _log "Download kubeconfig"
        _kubeconfig $CLUSTER_NAME
        _get_cluster_info $CLUSTER_NAME 
        _create_tuning_config $CLUSTER_NAME
    done
  ;;&
  *) ;;
esac

