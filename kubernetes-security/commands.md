
# 1 Kubernetes networks
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

# 2 Kubernetes Volumes

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

http://homework.otus/conf/key1

# 3 Kubernetes Security

## 1 Create Service accounts `monitoring` and `cd` 

```bash
kubectl apply -f monitoing_serviceAccount.yml
kubectl apply -f cd_serviceAccount.yml
```

## 2 Apply `metrics_reader` cluster role

```bash
kubectl apply -f metrics_reader_clusterRole.yml
```

## 3 Apply role bindings

```bash
kubectl apply -f monitoing_clusterRoleBinding.yml
kubectl apply -f cd_roleBinding.yml
```

## 4 Check /metrics.html

```bash
minikube tunnel
curl http://homework.otus/metrics.html
```

## 5 Create kubeconfig for serviceAccount `cd` (token lives 1d)

### 5.1 Generate token (1d)

```bash
kubectl create token cd -n homework --duration=24h > token
```

### 5.2 Generate kubeconfig

```bash
# Данные кластера
CLUSTER=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

# Токен
TOKEN=$(cat token)

# Собираем kubeconfig
cat > cd.kubeconfig <<EOF
apiVersion: v1
kind: Config
clusters:
- name: ${CLUSTER}
  cluster:
    certificate-authority-data: ${CA}
    server: ${SERVER}
contexts:
- name: cd-context
  context:
    cluster: ${CLUSTER}
    namespace: homework
    user: cd
current-context: cd-context
users:
- name: cd
  user:
    token: ${TOKEN}
EOF
```

### 5.3 Validate cd.kubeconfig

```bash
kubectl --kubeconfig=cd.kubeconfig get pods -n homework
```

```bash
NAME                     READY   STATUS    RESTARTS   AGE
nginx-84c85bdc55-dxd2d   1/1     Running   0          30m
nginx-84c85bdc55-nx88p   1/1     Running   0          30m
nginx-84c85bdc55-rhbhh   1/1     Running   0          30m
```

