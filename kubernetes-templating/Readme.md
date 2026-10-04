# Kubernetes templating

## Homework chart
### Requirements 
- minikube
- Traefik Gateway API
- Gateway CRDs

### Helm install

```bash
helm install homework ./homework-chart -n homework --create-namespace
```

### Validate

```bash
NAME: homework
LAST DEPLOYED: Sat Oct  3 14:35:07 2026
NAMESPACE: demo
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
NOTES:
Спасибо за установку homework (release: homework)!

═══════════════════════════════════════════════════════════════
  АДРЕС СЕРВИСА
═══════════════════════════════════════════════════════════════

Внутри кластера:
  http://nginx.demo.svc.cluster.local:80

Снаружи (через Gateway API):
  http://homework.otus
  → /           — index.html
  → /homepage   — redirect (307) на /index.html

  Проверить локально:
    kubectl port-forward -n demo svc/nginx 8080:80
    curl -H "Host: homework.otus" http://localhost:8080/
```


## Kafka chart PROD

### Helm install

```bash
helm install kafka oci://registry-1.docker.io/bitnamicharts/kafka `
  --version 26.5.0 `
  -n prod `
  --create-namespace `
  --set image.repository=bitnamilegacy/kafka `
  --set image.tag=3.5.2-debian-12-r9 `
  --set controller.replicaCount=5 `
  --set listeners.client.protocol=SASL_PLAINTEXT `
  --set listeners.interbroker.protocol=SASL_PLAINTEXT
```

### Validate

```bash
kubectl get all -n prod
```

```bash
NAME                     READY   STATUS    RESTARTS   AGE
pod/kafka-controller-0   1/1     Running   0          5m56s
pod/kafka-controller-1   1/1     Running   0          5m56s
pod/kafka-controller-2   1/1     Running   0          5m56s
pod/kafka-controller-3   1/1     Running   0          5m56s
pod/kafka-controller-4   1/1     Running   0          5m56s

NAME                                TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                      AGE
service/kafka                       ClusterIP   10.104.179.234   <none>        9092/TCP                     5m56s
service/kafka-controller-headless   ClusterIP   None             <none>        9094/TCP,9092/TCP,9093/TCP   5m56s

NAME                                READY   AGE
statefulset.apps/kafka-controller   5/5     5m56s
```

## Kafka chart dev

### Helm install

```bash
helm install kafka oci://registry-1.docker.io/bitnamicharts/kafka `
  --version 26.5.0 `
  -n dev `
  --create-namespace `
  --set image.repository=bitnamilegacy/kafka `
  --set image.tag=3.5.2-debian-12-r9 `
  --set controller.replicaCount=1 `
  --set listeners.client.protocol=SASL_PLAINTEXT `
  --set listeners.interbroker.protocol=SASL_PLAINTEXT
```

### Validate

```bash
kubectl get all -n dev
```

```bash
NAME                     READY   STATUS    RESTARTS   AGE
pod/kafka-controller-0   1/1     Running   0          17s
                         
NAME                                TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
service/kafka                       ClusterIP   10.109.105.72   <none>        9092/TCP                     17s
service/kafka-controller-headless   ClusterIP   None            <none>        9094/TCP,9092/TCP,9093/TCP   17s
                                                     
NAME                                READY   AGE         
statefulset.apps/kafka-controller   1/1     17s
```

## Helmfile

```bash
helmfile apply
```

Apply only prod
```bash
helmfile -l namespace=prod apply
```

Apply only dev
```bash
helmfile -l namespace=dev apply
```

Destroy
```bash
helmfile destroy
```