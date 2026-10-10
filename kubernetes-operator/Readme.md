# MySQL Operator

Kopf-оператор для управления MySQL через CRD `MySQL` (`otus.homework/v1`).  
Образ: `roflmaoinmysoul/mysql-operator:1.0.0`

## Требования

- Kubernetes ≥ 1.25
- kubectl ≥ 1.25
- StorageClass (например, `standard`)
- Образы `mysql:8.0` и `roflmaoinmysoul/mysql-operator:1.0.0` доступны

## Файлы

```
crd.yaml
serviceaccount.yaml
clusterrole.yaml
clusterrolebinding.yaml
deployment.yaml
my-mysql.yaml
```

## Установка

```bash
# 1. Namespace оператора
kubectl create namespace mysql-operator-system

# 2. CRD
kubectl apply -f crd.yaml

# 3. ServiceAccount
kubectl apply -f serviceaccount.yaml

# 4. RBAC
kubectl apply -f clusterrole.yaml
kubectl apply -f clusterrolebinding.yaml

# 5. Deployment оператора
kubectl apply -f operator_deployment.yaml
```

### Проверка установки

```bash
kubectl get crd mysqls.otus.homework
kubectl get sa -n mysql-operator-system mysql-operator
kubectl get clusterrole mysql-operator
kubectl get clusterrolebinding mysql-operator -o jsonpath='{.roleRef.name}'   # ожидается: mysql-operator
kubectl get pods -n mysql-operator-system
```

## Создание MySQL

```bash
kubectl apply -f my-mysql.yaml
```

Пример CR:

```yaml
apiVersion: otus.homework/v1
kind: MySQL
metadata:
  name: my-mysql
  namespace: default
spec:
  image: "mysql:8.0"
  database: "appdb"
  password: "supersecret"
  storage_size: "1Gi"
```

## Валидация

```bash
# 1. CR создан и обработан
kubectl get mysql -A
kubectl get mysql my-mysql -n default -o yaml | Select-String "success: true"

# 2. Ресурсы созданы оператором
kubectl get pv,pvc,svc,deploy,pods -n default | Select-String my-mysql
# pv/my-mysql-pv        Bound
# pvc/my-mysql-pvc      Bound
# svc/my-mysql          ClusterIP 3306/TCP
# deploy/my-mysql       1/1
# pod/my-mysql-xxx-yyy  1/1 Running

# 3. MySQL отвечает
kubectl exec -n default deploy/my-mysql -- mysql -u root -psupersecret -e "SELECT 1;"

# 4. База создана
kubectl exec -n default deploy/my-mysql -- mysql -u root -psupersecret -e "SHOW DATABASES;"
# appdb

# 5. Логи оператора
kubectl logs -n mysql-operator-system deploy/mysql-operator --tail=20
# ... Handler 'mysql_on_create' succeeded.
```

### Чек-лист

| # | Проверка | Ожидаемо |
|---|----------|----------|
| 1 | `kubectl get crd mysqls.otus.homework` | существует |
| 2 | `kubectl get mysql -A` | `my-mysql` |
| 3 | `success: true` в status | да |
| 4 | PV/PVC | `Bound` |
| 5 | Deployment | `1/1` |
| 6 | Pod | `Running` |
| 7 | `SELECT 1` | `1` |
| 8 | `SHOW DATABASES` | `appdb` |

## Удаление

```bash
kubectl delete mysql my-mysql -n default
kubectl delete pv my-mysql-pv --ignore-not-found
kubectl delete pvc my-mysql-pvc -n default --ignore-not-found
```

## Известные проблемы

| Симптом | Причина | Решение |
|---------|---------|---------|
| `WARNING Not enough permissions to watch` | Kopf в cluster-wide режиме смотрит все CRD не только mysqls | Игнорировать или `args: ["--namespace","default"]` |
| `409 Conflict persistentvolumes "my-mysql-pv" already exists` | Оператор не идемпотентен | Удалить PV/PVC перед повторным созданием CR |

## RBAC

| Ресурс | API Group | Verbs |
|--------|-----------|-------|
| `mysqls` | `otus.homework` | `*` |
| `mysqls/status` | `otus.homework` | `get`, `update`, `patch` |
| `mysqls/finalizers` | `otus.homework` | `update` |
| `services` | `""` | CRUD |
| `persistentvolumeclaims` | `""` | CRUD |
| `persistentvolumes` | `""` | `get`, `list`, `watch`, `create`, `delete` |
| `deployments` | `apps` | CRUD |
| `deployments/status` | `apps` | `get` |
| `pods` | `""` | `get`, `list`, `watch` |
| `events` | `""` | `get`, `list`, `watch`, `create`, `patch` |

## Ограничения

- Deployment создаётся в `default`, не в namespace CR.
- PV создаётся с фиксированным именем `my-mysql-pv` — только один CR на кластер.
- Оператор не идемпотентен — повторное создание CR требует удаления PV.