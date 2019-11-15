#!/bin/bash

# This script handles the creation of multiple clusters using kind

NUM_CLUSTERS="${NUM_CLUSTERS:-2}"

_username="drone"
_password="drone"
_exchange_name="drone-exchange"
_pattern=".*drone.*"
_set_name="drone"
_policy_name="federate-drone"
_namespace="drone"
federation_upstream_set=""

declare -a clusters_name
declare -a clusters_ip

#: <<'END'
for i in $(seq ${NUM_CLUSTERS})
do
	echo " --------------- Number $i --------------- "
  kind create cluster --config cluster.yaml --name cluster$i
  echo "Number $i Created. export... "
  export KUBECONFIG="$(kind get kubeconfig-path --name="cluster$i")"

  clusters_name[$i]="cluster$i"

  # Find Docker IP
  clusters_ip[$i]=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${clusters_name[$i]}-control-plane")
  echo "${clusters_name[$i]}-control-plane -> ${clusters_ip[$i]}"

  # Deploy rabbitmq
  kubectl create namespace ${_namespace}
  kubectl create -f rabbitDeploy/deployment.yaml --namespace ${_namespace}
  kubectl create -f rabbitDeploy/clusterip.yaml --namespace ${_namespace}
  kubectl create -f rabbitDeploy/nodeport.yaml --namespace ${_namespace}

  #watch kubectl get deployments,pods,services --namespace drone

  # Install Helm and Tiller
  # kubectl -n kube-system create serviceaccount tiller
  # kubectl create clusterrolebinding tiller   --clusterrole=cluster-admin   --serviceaccount=kube-system:tiller
  # helm init --service-account tiller

  # sleep 5s

  # watch kubectl get deployments,pods,services -A

  # Install RabbitMq with helm
  # helm install stable/rabbitmq-ha --name drone-rabbit --namespace rabbit -f rabbit-values.yaml
  # kubectl get deployments,pods,services --namespace drone

  # watch kubectl get deployments,pods,services --namespace drone
  # kubectl patch service drone-rabbit-rabbitmq-ha --namespace=rabbit --type='json' --patch='[{"op": "replace", "path": "/spec/ports/0/nodePort", "value":31000}]'

done

watch kubectl get deployments,pods,services --namespace ${_namespace}
#END
for j in $(seq ${NUM_CLUSTERS})
do
  echo $j
  echo "Federate ${clusters_name[$j]}"
  # pod_name=drone-rabbit-rabbitmq-ha-0
  export KUBECONFIG="$(kind get kubeconfig-path --name=${clusters_name[$j]})"

  pod_name=$(kubectl get pod -n ${_namespace} -o jsonpath="{.items[0].metadata.name}")

  kubectl exec -it $pod_name --namespace ${_namespace} -- bash -c "rabbitmq-plugins enable rabbitmq_federation rabbitmq_federation_management"
  kubectl exec -it $pod_name --namespace ${_namespace} rabbitmqctl add_user ${_username} ${_password}
  kubectl exec -it $pod_name --namespace ${_namespace} rabbitmqctl set_user_tags ${_username} administrator
  kubectl exec -it $pod_name --namespace ${_namespace} -- bash -c "rabbitmqctl set_permissions -p / ${_username} \".*\" \".*\" \".*\""

  for x in $(seq ${NUM_CLUSTERS})
  do
    if [ "${clusters_name[$x]}" != "${clusters_name[$j]}" ]
      then
        kubectl exec -it $pod_name --namespace ${_namespace} -- bash -c "rabbitmqctl set_parameter federation-upstream ${clusters_name[$x]} '{\"uri\":\"amqp://${_username}:${_password}@${clusters_ip[$x]}:31001\"}'"
    fi
  done

  federation_upstream_set="rabbitmqctl set_parameter federation-upstream-set ${_set_name} '["
  for x in $(seq ${NUM_CLUSTERS})
  do
    if [ "${clusters_name[$x]}" != "${clusters_name[$j]}" ]
      then
        federation_upstream_set="${federation_upstream_set} {\"upstream\":\"${clusters_name[$x]}\"},"
    fi
  done
  federation_upstream_set="${federation_upstream_set}]'"

  kubectl exec -it $pod_name --namespace ${_namespace} -- bash -c "${federation_upstream_set}"

  kubectl exec -it $pod_name --namespace ${_namespace} -- bash -c "rabbitmqctl set_policy --apply-to exchanges ${_policy_name} \"${_pattern}\" '{\"federation-upstream-set\":\"${_set_name}\"}'"

  # Install metrics-server
  kubectl create -f metric/metrics-server/deploy/1.8+/

  # Load and Deploy drone-agent
  # echo "Create image docker..."
  # cd ../drone
  # docker build -t drone-daemon-resources:first .
  # echo "Loading in kind..."
  # kind load docker-image drone-agent:first --name cluster1
  # kubectl apply -f drone-deploy.yaml

  # Create docker image, Load and Deploy drone-daemon-resources 
  # echo "Create image docker..."
  # cd ../drone_daemon_resources
  # docker build -t drone-daemon-resources:first .
  # echo "Loading in kind..."
  # kind load docker-image drone-daemon-resources:first --name cluster1
  # kubectl apply -f drone-daemon-resources.yml

done
