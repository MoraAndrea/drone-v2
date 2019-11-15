CLUSTER_NAME="${CLUSTER_NAME}"

echo "Create image docker..."
docker build -t drone-agent:first .

echo "Load image on kind..."
kind load docker-image drone-agent:first --name ${CLUSTER_NAME}

echo "Apply on K8S"
kubectl apply -f drone-deploy.yaml -n drone