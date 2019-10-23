echo "Create image docker..."
docker build -t drone-agent:first .

echo "Load image on kind..."
kind load docker-image drone-agent:first --name cluster1

# echo "Apply on K8S"
# kubectl apply -f drone-daemon-resources.yml