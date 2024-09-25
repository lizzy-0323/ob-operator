#!/bin/bash
 
# load all the parameters in setup.sh
source setup.sh
source util.sh
source env.sh
source case_p5_v222/env_vars.sh
 
# clean up delete everything by deleting the entire namespace
cleanup() {
    kubectl delete namespace $NAMESPACE
    rm -rf case_p5_v222/env_vars.sh
}

cleanClusteroperation() {
    local template_file=$1
    kubectl delete obclusteroperation $template_file -n $NAMESPACE
}

prepare() {
    export OP_SET_PARAMETERS=op-set-parameters-$SUFFIX
    kubectl create namespace $NAMESPACE
    create_pass_secret $NAMESPACE $OB_ROOT_SECRET $PASSWORD
    kubectl create serviceaccount $NAMESPACE -n $NAMESPACE 
}
 
run() {
    local template_file=$1
    echo $OBCLUSTER_NAME
    envsubst < ./config/2.2.2_test/$template_file | kubectl apply -f -
}

create() {
    local template_file=$1
    echo $OBCLUSTER_NAME
    envsubst < ./config/2.2.2_test/$template_file | kubectl create -f -
}

check_resource_running() {
    counter=0
    timeout=100  
    RESOURCE_RUNNING='false'
    while true; do
        echo 'check resource'
        counter=$((counter+1))
#        pod_1_zone1=`kubectl get pod  -o wide -n $NAMESPACE | grep $OBCLUSTER_NAME-1-zone1 |awk -F' ' '{print $2}'| awk 'NR==1'`
        ip=`kubectl get pod  -o wide -n $NAMESPACE | grep $OBCLUSTER_NAME-1-zone1 |awk -F' ' '{print $6}'| awk 'NR==1'`
        crd_obcluster=`kubectl get obcluster $OBCLUSTER_NAME -n $NAMESPACE  -o yaml| grep "status: running" | tail -n 1| sed 's/ //g'`
	crd_observer=`kubectl get observer -n $NAMESPACE  -o yaml| grep "status: running" | tail -n 1| sed 's/ //g'`
	crd_zone=`kubectl get obzone -n $NAMESPACE  -o yaml| grep "status: running" | tail -n 1| sed 's/ //g'`
        if [[ -n "$ip" && $crd_obcluster = "status:running" && $crd_obcluster = "status:running" && $crd_zone = "status:running"  ]];then
#            echo "pod_1_zone1 is $pod_1_zone1 ready"
            echo "svc is $ip ready"
            echo "crd_obcluster $crd_obcluster crd_obcluster $crd_obcluster crd_zone $crd_zone"
            RESOURCE_RUNNING='true'
            break
        fi
        if [ $counter -eq $timeout ]; then
            echo "resource still not running"
            break
        fi
        sleep 3s
    done
}
 
check_in_obcluster() {
    counter=0
    timeout=100  
    OBSERVER_ACTIVE='false'
    ip=`kubectl get pod  -o wide -n $NAMESPACE | grep $OBCLUSTER_NAME-1-zone1 |awk -F' ' '{print $6}'| awk 'NR==1'`
    echo $ip
    echo $PASSWORD
    while true; do
        echo 'check ob'
        counter=$((counter+1))
        server_1_zone1=`mysql -uroot -h $ip -P 2881 -Doceanbase -p$PASSWORD -e 'select * from __all_server;'|grep zone1|awk -F' ' '{print $11}'| awk 'NR==1'`
        echo $server_1_zone1
        if [[ $server_1_zone1 == "ACTIVE"  ]]
        then
            echo "server_1_zone1 $server_1_zone1"
            OBSERVER_ACTIVE='true'
            break
        fi
        if [ $counter -eq $timeout ]; then
            echo "resource still not running"
	    echo "case failed"
            break
        fi
        sleep 3s
    done
}

check_operation() {
    counter=0
    timeout=100  
    OPERATION_ACTIVE='false'
    ip=`kubectl get pod  -o wide -n $NAMESPACE | grep $OBCLUSTER_NAME-1-zone1 |awk -F' ' '{print $6}'| awk 'NR==1'`
    while true; do
        echo 'check obclusteroperation'
        counter=$((counter+1))
	obclusteroperation=`kubectl get obclusteroperation -n $NAMESPACE | grep $OP_SET_PARAMETERS |awk -F' ' '{print $3}'| tail -n 1`
        if [[ $obclusteroperation = "Succeeded"  ]]
        then
            echo "obclusteroperation $obclusteroperation"
            OPERATION_ACTIVE='true'
            break
        fi
        if [ $counter -eq $timeout ]; then
            echo "resource still not running"
            echo "case failed"
            break
        fi
        sleep 3s
    done
}

validate() {
    run "obcluster_template_new_sc.yaml"
    echo 'do validate'
    check_resource_running
    if [[ $RESOURCE_RUNNING == 'false' ]]; then
        echo "case failed"
    else
        check_in_obcluster
	create "op_set_parameters.yaml"
 	check_operation
	check_resource_running
        if [[ $OPERATION_ACTIVE == 'false' ]]; then
            echo "case failed"
            cleanup
	    prepare
        else
            echo "case passed"
        fi
    fi
}

prepare
validate
cleanup