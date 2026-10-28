# Kubernetes Logging Stack — README

Установка minikube с двумя нодами, настройка taint на инфраструктурной ноде, развёртывание SeaweedFS (S3), Loki, Promtail и Grafana двумя способами: через `values.yaml` и через `helmfile`.

---

## 1. Запуск minikube с двумя нодами

```bash
minikube start --nodes 2 --driver=docker
# для Linux/macOS с Docker: minikube start --nodes 2 --driver=docker
```

Проверка:

```bash
kubectl get nodes
```

Ожидается две ноды: `minikube` (control-plane) и `minikube-m02` (worker).

> **Важно для multi-node minikube**: стандартный `storage-provisioner` (hostPath) не поддерживает многонодовые кластеры. Включите CSI-драйвер, поддерживающий динамическое выделение томов:
>
> ```bash
> minikube addons enable csi-hostpath-driver
> ```

---

## 2. Настройка инфраструктурной ноды

Назначьте лейбл и taint на worker-ноду (`minikube-m02`):

```bash
# Лейбл для планирования инфраструктурных подов
kubectl label node minikube-m02 node-role=infra

# Taint, запрещающий планирование посторонних подов
kubectl taint node minikube-m02 node-role=infra:NoSchedule
```

Проверка:

```bash
kubectl describe node minikube-m02 | grep -E "Taints|node-role"
```

Ожидаемый вывод:

```
Taints:             node-role=infra:NoSchedule
node-role=infra
```

### Снять taint (если нужно откатить)

```bash
kubectl taint node minikube-m02 node-role=infra:NoSchedule-
```

---

## 3. Вывод конфигурации нод (для ДЗ)

Выполните и приложите к отчёту:

```bash
kubectl get node -o wide --show-labels
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
```

Пример ожидаемого вывода:

```
NAME           STATUS   ROLES           AGE   VERSION   INTERNAL-IP    EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION     NAME           STATUS   ROLES           AGE     VERSION   INTERNAL-IP    EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION                              CONTAINER-RUNTIME    LABELS
minikube       Ready    control-plane   6d23h   v1.37.0   192.168.49.2   <none>        Debian GNU/Linux 12 (bookworm)   6.18.33.2-microsoft-standard-WSL2 (amd64)   containerd://2.3.4   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,kubernetes.io/arch=amd64,kubernetes.io/hostname=minikube,kubernetes.io/os=linux,minikube.k8s.io/commit=7a9f6a841470a207de8cf4bafcccee0969d8ba10,minikube.k8s.io/name=minikube,minikube.k8s.io/primary=true,minikube.k8s.io/updated_at=2026_10_19T20_58_34_0700,minikube.k8s.io/version=v1.39.0,node-role.kubernetes.io/control-plane=,node.kubernetes.io/exclude-from-external-load-balancers=,topology.hostpath.csi/node=minikube
minikube-m02   Ready    <none>          6d23h   v1.37.0   192.168.49.3   <none>        Debian GNU/Linux 12 (bookworm)   6.18.33.2-microsoft-standard-WSL2 (amd64)   containerd://2.3.4   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,kubernetes.io/arch=amd64,kubernetes.io/hostname=minikube-m02,kubernetes.io/os=linux,minikube.k8s.io/commit=7a9f6a841470a207de8cf4bafcccee0969d8ba10,minikube.k8s.io/name=minikube,minikube.k8s.io/primary=false,minikube.k8s.io/updated_at=2026_10_19T20_59_23_0700,minikube.k8s.io/version=v1.39.0,node-role=infra
```

```
NAME           TAINTS
minikube       <none>
minikube-m02   [map[effect:NoSchedule key:node-role value:infra]]
```

Приложите фактический вывод ваших команд в отчёт.

---

## 4. Вариант 2: Установка через `helmfile`

Создайте `helmfile.yaml` в корне проекта:

```yaml
repositories:
  - name: grafana
    url: https://grafana.github.io/helm-charts
  - name: seaweedfs
    url: https://seaweedfs.github.io/seaweedfs/helm

releases:
  - name: seaweedfs
    namespace: seaweedfs
    createNamespace: true
    chart: seaweedfs/seaweedfs
    values:
      - allInOne:
          enabled: true
          data:
            type: emptyDir
          s3:
            enabled: true
          nodeSelector: |
            node-role: infra
          tolerations: |
            - key: "node-role"
              operator: "Equal"
              value: "infra"
              effect: "NoSchedule"
      - s3:
          createBuckets:
            - name: loki
          createBucketsHook:
            nodeSelector: |
              node-role: infra
            tolerations: |
              - key: "node-role"
                operator: "Equal"
                value: "infra"
                effect: "NoSchedule"

  - name: loki
    namespace: logging
    createNamespace: true
    chart: grafana/loki
    version: 7.5.0
    needs: [seaweedfs/seaweedfs]
    values:
      - loki:
          auth_enabled: false
          commonConfig:
            replication_factor: 1
          schemaConfig:
            configs:
              - from: "2024-04-01"
                store: tsdb
                object_store: s3
                schema: v13
                index:
                  prefix: loki_index_
                  period: 24h
          storage:
            type: s3
            bucketNames:
              chunks: loki
              ruler: loki
            s3:
              endpoint: http://seaweedfs-s3.seaweedfs.svc.cluster.local:8333
              access_key_id: <access-key>
              secret_access_key: <secret-key>
              s3forcepathstyle: true
              insecure: true
          limits_config:
            allow_structured_metadata: true
            volume_enabled: true
      - deploymentMode: SingleBinary
      - singleBinary:
          enabled: true
          replicas: 1
          persistence:
            enabled: true
            size: 10Gi
            storageClass: standard
          podSecurityContext:
            fsGroup: 10001
            fsGroupChangePolicy: OnRootMismatch
          nodeSelector:
            node-role: infra
          tolerations:
            - key: "node-role"
              operator: "Equal"
              value: "infra"
              effect: "NoSchedule"
          initContainers:
            - name: fix-permissions
              image: busybox:1.36
              command: ["sh", "-c", "chown -R 10001:10001 /var/loki"]
              securityContext:
                runAsUser: 0
                runAsNonRoot: false
              volumeMounts:
                - name: storage
                  mountPath: /var/loki
      - backend: { replicas: 0 }
      - read: { replicas: 0 }
      - write: { replicas: 0 }
      - ingester: { replicas: 0 }
      - querier: { replicas: 0 }
      - queryFrontend: { replicas: 0 }
      - queryScheduler: { replicas: 0 }
      - distributor: { replicas: 0 }
      - compactor: { replicas: 0 }
      - indexGateway: { replicas: 0 }
      - ruler: { replicas: 0 }
      - gateway: { enabled: false }
      - minio: { enabled: false }

  - name: promtail
    namespace: logging
    chart: grafana/promtail
    version: 6.16.6
    needs: [logging/loki]
    values:
      - config:
          clients:
            - url: http://loki.logging.svc.cluster.local:3100/loki/api/v1/push
        tolerations:
          - key: "node-role"
            operator: "Equal"
            value: "infra"
            effect: "NoSchedule"

  - name: grafana
    namespace: logging
    chart: grafana/grafana
    version: 8.5.0
    needs: [logging/loki]
    values:
      - nodeSelector:
          node-role: infra
        tolerations:
          - key: "node-role"
            operator: "Equal"
            value: "infra"
            effect: "NoSchedule"
      - datasources:
          datasources.yaml:
            apiVersion: 1
            datasources:
              - name: Loki
                type: loki
                url: http://loki.logging.svc.cluster.local:3100
                access: proxy
                isDefault: true
                editable: false
```

Применение:

```bash
# Предварительный просмотр
helmfile diff

# Применить
helmfile apply
```

Если `helmfile` не установлен:

```bash
# Linux/macOS
brew install helmfile
# или
curl -L https://github.com/helmfile/helmfile/releases/latest/download/helmfile_linux_amd64 -o /usr/local/bin/helmfile
chmod +x /usr/local/bin/helmfile

# Windows (PowerShell)
winget install helmfile
# или
scoop install helmfile
```

---

## 5. Проверка работоспособности

### 5.1 Поды на инфраструктурной ноде

```bash
kubectl get pods -n logging -o wide
kubectl get pods -n seaweedfs -o wide
```

Все поды (`loki-0`, `grafana-*`, `seaweedfs-*`) должны быть на `minikube-m02`. `promtail-*` — на обеих нодах.

### 5.2 Loki принимает данные

```bash
kubectl run -n logging tmp-curl --rm -it --image=curlimages/curl --restart=Never -- \
  curl -s http://loki:3100/loki/api/v1/labels
```

Ожидается непустой список меток:

```json
{"status":"success","data":["app","component","container","filename","instance","job","namespace","node_name","pod","service_name","stream"]}
```

### 5.3 Grafana показывает логи

```bash
kubectl port-forward -n logging svc/grafana 3000:80
minikube service grafana -n logging --url # for minikube on windows with docker
```

Пароль Grafana
```bash
 kubectl get secret -n logging grafana -o jsonpath="{.data.admin-password}" | %{[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_))}
```
Откройте `http://localhost:3000` → **Explore** → datasource **Loki** → запрос:

```logql
{job=~".+"}
```

Временной диапазон — **Last 15 minutes**. Если строки отображаются — стек работает.

---

## 6. Troubleshooting

| Проблема | Решение |
|---|---|
| `loki-0` падает с `permission denied` на `/var/loki` | В minikube `fsGroup` не работает для `hostPath`. Добавьте `initContainers` с `chown` и `runAsNonRoot: false` |
| `initContainer` падает с `breaks non-root policy` | Добавьте `runAsNonRoot: false` в `securityContext` init-контейнера |
| `field is immutable` при `helm upgrade` | Удалите StatefulSet без удаления подов: `kubectl delete statefulset loki -n logging --cascade=orphan` |
| Promtail: `connection refused` | Loki ещё не готов. Перезапустите Promtail: `kubectl delete pod -n logging -l app.kubernetes.io/name=promtail` |
| Grafana пуста, но Loki отвечает | Проверьте URL datasource (без `/loki/api/v1/push`) и временной диапазон в Explore |
| `ImagePullBackOff` для MinIO/MariaDB | Bitnami удалила бесплатные образы. Используйте официальный чарт SeaweedFS вместо Bitnami |