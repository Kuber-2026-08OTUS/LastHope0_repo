
# Kubernetes networks
## Apply application manifests

```bash
kubectl apply -f namespace.yml
kubectl apply -f deployment.yml
kubectl apply -f service.yml
```

## Install API Gateway traefic

### Install/update the Kubernetes Gateway API CRDs.

```bash
# Install Gateway API CRDs from the Standard channel.
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml
```

### Install traefik

```bash
kubectl apply -f .\traefik\namespace.yml

helm install traefik traefik/traefik -f traefik\values.yml -n traefik --wait
```

## Configure Gateway API

```bash

kubectl apply -f gateway.yml
kubectl apply -f httpRoute.yml
```

## Verify 

### Minikube tunnel

Run as admin
```bash
minikube tunnel
```

### Modify hosts 

Figure out IP of traefik LB service
```bash
kubectl get svc traefik -n traefik
```

Change `C:\Windows\System32\drivers\etc\hosts`
```
127.0.0.1 homework.otus
```

### Open site

Open in your browser 

http://homework.otus/
http://homework.otus/homepage

# Kubernetes Volumes

## Create SC, PV, PVS

```bash
kubectl apply -f storageClass.yml
kubectl apply -f pvc.yml
kubectl apply -f cm.yml
```

### Validate

```bash
kubectl get sc -n homework
kubectl get pv -n homework
kubectl get pvc -n homework
kubectl get cm -n homework
```

## Apply deployment.yaml
```bash
kubectl apply -f deployment.yml
```