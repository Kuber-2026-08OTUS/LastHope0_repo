## 1. Кластер Minikube

### Описание
Задание выполнялось в локальном кластере **Minikube** с тремя нодами. Yandex Cloud не использовался. 

### Команды и конфиги
Команда запуска кластера:

```bash
    minikube start --nodes 3 --cpus 2 --memory 4096
```

### Валидация
Проверка готовности нод (одинаково для PS и Bash):

```bash
  kubectl get nodes
  # Ожидается: minikube, minikube-m02, minikube-m03 — все Ready
```

Проверка состояния кластера:
```bash
kubectl cluster-info
kubectl get pods -A
# Все системные поды (kube-apiserver, etcd, coredns, kube-proxy, storage-provisioner) в состоянии Running
```

## 2. Установка Consul

### Описание
В namespace `consul` установлен Consul из OCI-чарта Bitnami с тремя репликами сервера. Использованы legacy-образы `bitnamilegacy/consul` и `bitnamilegacy/os-shell`, так как оригинальные образы Bitnami стали недоступны. Включён `volumePermissions` для исправления прав на том данных. Дополнительно создан сервис `consul-api` (ClusterIP), так как чарт Bitnami создаёт только headless-сервис `consul-headless`, а Vault требуется стабильный адрес для подключения.

### Команды и конфиги
Создайте файл `consul-values.yaml`:

```yaml
replicaCount: 3

image:
  registry: docker.io
  repository: bitnamilegacy/consul
  tag: 1.21.4-debian-12-r1

volumePermissions:
  enabled: true
  image:
    registry: docker.io
    repository: bitnamilegacy/os-shell
    tag: 12-debian-12-r50
```

Создайте файл `consul-api-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: consul-api
  namespace: consul
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: consul
    app.kubernetes.io/instance: consul
  ports:
    - name: http
      port: 8500
      targetPort: 8500
```

Установка Consul (PowerShell):

```powershell
helm install consul oci://registry-1.docker.io/bitnamicharts/consul `
  --namespace consul `
  --create-namespace `
  -f consul-values.yaml
```

Установка Consul (Bash):

```bash
helm install consul oci://registry-1.docker.io/bitnamicharts/consul \
  --namespace consul \
  --create-namespace \
  -f consul-values.yaml
```

Примените сервис `consul-api` (одинаково для PS и Bash):

```bash
kubectl apply -f consul-api-service.yaml
```

### Валидация
Проверка подов Consul (одинаково для PS и Bash):

```bash
kubectl get pods -n consul
# Ожидается: 3 пода consul-0, consul-1, consul-2 в статусе Running
```

Проверка членов кластера:

```bash
kubectl exec -n consul consul-0 -- consul members
# Ожидается: 3 сервера в статусе alive
```

Проверка состояния Raft:

```bash
kubectl exec -n consul consul-0 -- consul operator raft list-peers
# Ожидается: 1 leader, 2 follower, все alive
```

Проверка сервиса `consul-api`:

```bash
kubectl get svc consul-api -n consul
# Ожидается: ClusterIP с портом 8500
```

## 3. Установка Vault

### Описание
В namespace `vault` установлен Vault из OCI-чарта Bitnami в HA-режиме (3 реплики). Использованы legacy-образы `bitnamilegacy/vault`, `bitnamilegacy/vault-k8s` и `bitnamilegacy/os-shell`. Vault сконфигурирован на использование ранее установленного Consul в качестве storage backend (HA). Добавлен init-контейнер `fix-permissions` для исправления прав на том данных (UID 1001). В конфигурации указан адрес сервиса `consul-api.consul.svc.cluster.local:8500`, созданного на предыдущем шаге.

### Команды и конфиги
Создайте файл `vault-values.yaml`:

```yaml
global:
  security:
    allowInsecureImages: true

server:
  image:
    registry: docker.io
    repository: bitnamilegacy/vault
    tag: 1.16.2-debian-12-r2

  replicaCount: 3

  initContainers:
    - name: fix-permissions
      image: docker.io/bitnamilegacy/os-shell:12-debian-12-r36
      command: ["/bin/bash", "-ec", "chown -R 1001:1001 /bitnami/vault/data"]
      securityContext:
        runAsUser: 0
      volumeMounts:
        - name: data
          mountPath: /bitnami/vault/data

  config: |
    ui = true
    disable_mlock = true
    listener "tcp" {
      tls_disable = 1
      address = "[::]:8200"
      cluster_address = "[::]:8201"
    }
    storage "consul" {
      path = "vault"
      address = "consul-api.consul.svc.cluster.local:8500"
    }

injector:
  image:
    registry: docker.io
    repository: bitnamilegacy/vault-k8s
    tag: 1.4.2-debian-12-r0
```

Установка Vault (PowerShell):

```powershell
helm install vault oci://registry-1.docker.io/bitnamicharts/vault `
  --namespace vault `
  --create-namespace `
  -f vault-values.yaml
```

Установка Vault (Bash):

```bash
helm install vault oci://registry-1.docker.io/bitnamicharts/vault \
  --namespace vault \
  --create-namespace \
  -f vault-values.yaml
```

### Валидация
Проверка подов Vault (одинаково для PS и Bash):

```bash
kubectl get pods -n vault
# Ожидается: 3 пода vault-server-0, vault-server-1, vault-server-2 в статусе Running (0/1 до unseal)
```

Проверка логов Vault на отсутствие ошибок прав и использование Consul:

```bash
kubectl logs -n vault vault-server-0 --tail=20
# В логах должно быть указано Storage: consul (HA available), без ошибок permission denied
```

Проверка, что init-контейнер `fix-permissions` завершился успешно:

```bash
kubectl get pod vault-server-0 -n vault -o jsonpath='{.status.initContainerStatuses[0].state}'
# Ожидается: terminated с exitCode 0
```

## 4. Инициализация и распечатка (Unseal) Vault

### Описание
Выполнена инициализация Vault на поде `vault-server-0` с параметрами `-key-shares=1 -key-threshold=1`. Полученные ключи (unseal key и root token) сохранены в локальный файл `cluster-keys.json`. Затем извлечён unseal key и выполнена распечатка (unseal) всех трёх подов Vault: `vault-server-0`, `vault-server-1`, `vault-server-2`. После успешного unseal все поды перешли в состояние `1/1 Running`, Vault использует Consul как storage backend и работает в HA-режиме (один активный, два standby).

### Команды и конфиги
Инициализация Vault (только на `vault-server-0`). Команда одинакова для PowerShell и Bash:

```bash
kubectl exec -n vault vault-server-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json > cluster-keys.json
```

Извлечение unseal key и распечатка всех подов (PowerShell):

```powershell
$VAULT_UNSEAL_KEY = (Get-Content cluster-keys.json | ConvertFrom-Json).unseal_keys_b64[0]
kubectl exec -n vault vault-server-0 -- vault operator unseal $VAULT_UNSEAL_KEY
kubectl exec -n vault vault-server-1 -- vault operator unseal $VAULT_UNSEAL_KEY
kubectl exec -n vault vault-server-2 -- vault operator unseal $VAULT_UNSEAL_KEY
```

Извлечение unseal key и распечатка всех подов (Bash):

```bash
VAULT_UNSEAL_KEY=$(cat cluster-keys.json | jq -r ".unseal_keys_b64[]")
kubectl exec -n vault vault-server-0 -- vault operator unseal $VAULT_UNSEAL_KEY
kubectl exec -n vault vault-server-1 -- vault operator unseal $VAULT_UNSEAL_KEY
kubectl exec -n vault vault-server-2 -- vault operator unseal $VAULT_UNSEAL_KEY
```

### Валидация
Проверка статуса Vault на активном поде (одинаково для PS и Bash):

```bash
kubectl exec -n vault vault-server-0 -- vault status
# Ожидается: Sealed: false, HA Enabled: true, Storage Type: consul
```

Проверка статуса на остальных подах:

```bash
kubectl exec -n vault vault-server-1 -- vault status
kubectl exec -n vault vault-server-2 -- vault status
# Ожидается: Sealed: false
```

Проверка, что все поды Vault готовы:

```bash
kubectl get pods -n vault
# Ожидается: все три пода vault-server-* в статусе 1/1 Running
```

## 5. Создание секрета в Vault

### Описание
В Vault включён KV Secret Engine версии 1 по пути `otus/`. В нём создан секрет `otus/cred` с двумя полями: `username='otus'` и `password='asajkjkahs'`. Все операции выполняются на поде `vault-server-0` с использованием root-токена, полученного при инициализации (файл `cluster-keys.json`).

### Команды и конфиги
Извлеките root-токен из `cluster-keys.json` (PowerShell):

```powershell
$VAULT_ROOT_TOKEN = (Get-Content cluster-keys.json | ConvertFrom-Json).root_token
```

Извлеките root-токен из `cluster-keys.json` (Bash):

```bash
VAULT_ROOT_TOKEN=$(cat cluster-keys.json | jq -r ".root_token")
```

Выполните логин в Vault с root-токеном (PowerShell):

```powershell
kubectl exec -n vault vault-server-0 -- vault login $VAULT_ROOT_TOKEN
```

Выполните логин в Vault с root-токеном (Bash):

```bash
kubectl exec -n vault vault-server-0 -- vault login $VAULT_ROOT_TOKEN
```

Включите KV Secret Engine версии 1 по пути `otus/` (команда одинакова для PS и Bash):

```bash
kubectl exec -n vault vault-server-0 -- vault secrets enable -path=otus -version=1 kv
```

Создайте секрет `otus/cred` (команда одинакова для PS и Bash):

```bash
kubectl exec -n vault vault-server-0 -- vault kv put otus/cred username='otus' password='asajkjkahs'
```

### Валидация
Проверьте, что секрет создан и содержит корректные значения (одинаково для PS и Bash):

```bash
kubectl exec -n vault vault-server-0 -- vault kv get otus/cred
# Ожидается: отображение username=otus, password=asajkjkahs
```

Проверьте список включённых secret engine:

```bash
kubectl exec -n vault vault-server-0 -- vault secrets list
# Ожидается: наличие пути otus/ с типом kv
```

## 6. Создание ServiceAccount и RBAC

### Описание
В namespace `vault` создан ServiceAccount `vault-auth`. Для него создан ClusterRoleBinding `vault-auth-delegator`, привязывающий его к встроенной ClusterRole `system:auth-delegator`. Эта роль даёт права на создание `tokenreviews` и `subjectaccessreviews`, что необходимо Vault для проверки токенов клиентов через Kubernetes API при аутентификации `auth/kubernetes`.

### Команды и конфиги
Создайте файл `vault-auth-rbac.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-auth
  namespace: vault
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-auth-delegator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
  - kind: ServiceAccount
    name: vault-auth
    namespace: vault
```

Примените манифест (одинаково для PowerShell и Bash):

```bash
kubectl apply -f vault-auth-rbac.yaml
```

### Валидация
Проверьте, что ServiceAccount создан (одинаково для PS и Bash):

```bash
kubectl get sa vault-auth -n vault
# Ожидается: ServiceAccount vault-auth существует
```

Проверьте, что ClusterRoleBinding создан и привязан к нужному SA:

```bash
kubectl get clusterrolebinding vault-auth-delegator -o yaml
# В subjects должен быть ServiceAccount vault-auth в namespace vault
```

Проверьте, что у SA есть права на создание tokenreviews:

```bash
kubectl auth can-i create tokenreviews --as=system:serviceaccount:vault:vault-auth
# Ожидается: yes
```

Проверьте, что у SA есть права на создание subjectaccessreviews:

```bash
kubectl auth can-i create subjectaccessreviews --as=system:serviceaccount:vault:vault-auth
# Ожидается: yes
```

## 7. Настройка auth/kubernetes в Vault

### Описание
В Vault включён метод аутентификации `auth/kubernetes`. Для его конфигурации получен токен ServiceAccount `vault-auth` (через `kubectl create token`) и CA-сертификат кластера. В качестве CA использован сертификат `~/.minikube/ca.crt`, так как внутренний CA, смонтированный в под Vault (`/var/run/secrets/kubernetes.io/serviceaccount/ca.crt`), оказался невалидным и вызывал предупреждение `Configured CA PEM data contains no valid certificates`. Vault сконфигурирован с параметрами `token_reviewer_jwt`, `kubernetes_ca_cert` и `kubernetes_host="https://kubernetes.default.svc"`. Это позволяет Vault проверять токены клиентов через Kubernetes API (TokenReview).

### Команды и конфиги
Получите токен для ServiceAccount `vault-auth` (команда одинакова для PowerShell и Bash):

```bash
kubectl create token vault-auth -n vault --duration=8760h
```

Сохраните токен и CA-сертификат в переменные (PowerShell):

```powershell
$SA_TOKEN = kubectl create token vault-auth -n vault --duration=8760h
$SA_CA = Get-Content -Raw -Path "$HOME\.minikube\ca.crt"
```

Сохраните токен и CA-сертификат в переменные (Bash):

```bash
SA_TOKEN=$(kubectl create token vault-auth -n vault --duration=8760h)
SA_CA=$(cat ~/.minikube/ca.crt)
```

Включите метод аутентификации `auth/kubernetes` (команда одинакова для PS и Bash):

```bash
kubectl exec -n vault vault-server-0 -- vault auth enable kubernetes
```

Сконфигурируйте `auth/kubernetes` (PowerShell):

```powershell
kubectl exec -n vault vault-server-0 -- vault write auth/kubernetes/config `
  token_reviewer_jwt="$SA_TOKEN" `
  kubernetes_ca_cert="$SA_CA" `
  kubernetes_host="https://kubernetes.default.svc"
```

Сконфигурируйте `auth/kubernetes` (Bash):

```bash
kubectl exec -n vault vault-server-0 -- vault write auth/kubernetes/config \
  token_reviewer_jwt="$SA_TOKEN" \
  kubernetes_ca_cert="$SA_CA" \
  kubernetes_host="https://kubernetes.default.svc"
```

### Валидация
Проверьте конфигурацию `auth/kubernetes` (одинаково для PS и Bash):

```bash
kubectl exec -n vault vault-server-0 -- vault read auth/kubernetes/config
# Ожидается: kubernetes_host = https://kubernetes.default.svc
#            token_reviewer_jwt_set = true
#            kubernetes_ca_cert присутствует (не пустой)
```

Проверьте логи Vault на отсутствие предупреждений о CA-сертификате:

```bash
kubectl logs -n vault vault-server-0 --tail=20
# Не должно быть строк: Configured CA PEM data contains no valid certificates
```

Проверьте, что метод аутентификации включён:

```bash
kubectl exec -n vault vault-server-0 -- vault auth list
# Ожидается: наличие пути kubernetes/ с типом kubernetes
```

## 8. Создание политики otus-policy

### Описание
Создана политика Vault `otus-policy`, разрешающая только чтение (`read`) и просмотр списка (`list`) для секрета по пути `otus/cred`. Политика оформлена в виде файла `otus-policy.hcl` и применена в Vault. В дальнейшем эта политика будет назначена роли `auth/kubernetes/role/otus`, чтобы токены, выданные через Kubernetes-аутентификацию, имели доступ только к указанному секрету.

### Команды и конфиги
Создайте файл `otus-policy.hcl`:

```hcl
path "otus/cred" {
  capabilities = ["read", "list"]
}
```

Примените политику в Vault (PowerShell):

```powershell
Get-Content otus-policy.hcl -Raw | kubectl exec -i -n vault vault-server-0 -- vault policy write otus-policy -
```

Примените политику в Vault (Bash):

```bash
cat otus-policy.hcl | kubectl exec -i -n vault vault-server-0 -- vault policy write otus-policy -
```

### Валидация
Проверьте, что политика создана и содержит правильные правила (одинаково для PS и Bash):

```bash
kubectl exec -n vault vault-server-0 -- vault policy read otus-policy
# Ожидается: path "otus/cred" { capabilities = ["read", "list"] }
```

Проверьте список политик:

```bash
kubectl exec -n vault vault-server-0 -- vault policy list
# Ожидается: наличие политики otus-policy
```

## 9. Создание роли auth/kubernetes/role/otus

### Описание
В Vault создана роль `auth/kubernetes/role/otus`, которая связывает Kubernetes ServiceAccount `vault-auth` из namespace `vault` с политикой `otus-policy`. Роль разрешает аутентификацию только для указанного ServiceAccount и namespace, выдаёт токен с TTL 1 час и обязательной аудиторией `vault`. Параметр `audience=vault` необходим начиная с Vault 1.21+ и должен совпадать с аудиторией, запрашиваемой клиентом (External Secrets Operator) в SecretStore.

### Команды и конфиги
Команда создания роли одинакова для PowerShell и Bash:

```bash
kubectl exec -n vault vault-server-0 -- vault write auth/kubernetes/role/otus \
  bound_service_account_names=vault-auth \
  bound_service_account_namespaces=vault \
  policies=otus-policy \
  ttl=1h \
  audience=vault
```

Для PowerShell при необходимости можно записать в одну строку без переносов:

```powershell
kubectl exec -n vault vault-server-0 -- vault write auth/kubernetes/role/otus bound_service_account_names=vault-auth bound_service_account_namespaces=vault policies=otus-policy ttl=1h audience=vault
```

### Валидация
Проверьте, что роль создана и содержит правильные параметры (одинаково для PS и Bash):

```bash
kubectl exec -n vault vault-server-0 -- vault read auth/kubernetes/role/otus
# Ожидается:
# bound_service_account_names = [vault-auth]
# bound_service_account_namespaces = [vault]
# policies = [otus-policy]
# audience = vault
# ttl = 1h
```

Проверьте список ролей Kubernetes-аутентификации:

```bash
kubectl exec -n vault vault-server-0 -- vault list auth/kubernetes/role
# Ожидается: наличие роли otus
```

## 10. Установка External Secrets Operator

### Описание
В namespace `vault` установлен External Secrets Operator (ESO) из официального OCI-чарта. Включены установка CRD (`installCRDs: true`) и право на создание токенов для ServiceAccount (`rbac.serviceAccountTokenCreate: true`). Это право необходимо, чтобы ESO мог создать токен для ServiceAccount `vault-auth` и предъявить его Vault для аутентификации через `auth/kubernetes`. Без этого права Vault возвращал бы ошибку `403 permission denied`.

### Команды и конфиги
Создайте файл `eso-values.yaml`:

```yaml
installCRDs: true
rbac:
  serviceAccountTokenCreate: true
```

Установка ESO (PowerShell):

```powershell
helm upgrade --install external-secrets `
  oci://ghcr.io/external-secrets/charts/external-secrets `
  --namespace vault `
  -f eso-values.yaml
```

Установка ESO (Bash):

```bash
helm upgrade --install external-secrets \
  oci://ghcr.io/external-secrets/charts/external-secrets \
  --namespace vault \
  -f eso-values.yaml
```

### Валидация
Проверьте, что поды ESO запущены (одинаково для PS и Bash):

```bash
kubectl get pods -n vault -l app.kubernetes.io/name=external-secrets
# Ожидается: поды external-secrets, external-secrets-webhook, external-secrets-cert-controller в статусе Running
```

Проверьте статус Helm-релиза:

```bash
helm list -n vault
# Ожидается: релиз external-secrets в статусе deployed
```

Проверьте, что право на создание токенов включено (одинаково для PS и Bash):

```bash
kubectl auth can-i create serviceaccounts --subresource=token --as=system:serviceaccount:vault:external-secrets -n vault
# Ожидается: yes
```

## 11. Создание SecretStore

### Описание
В namespace `vault` создан объект `SecretStore` с именем `vault-backend`, который описывает подключение External Secrets Operator к Vault. SecretStore использует провайдер Vault с путём `otus`, версией KV `v1` и Kubernetes-аутентификацией через роль `otus` и ServiceAccount `vault-auth`. В `serviceAccountRef` указаны две аудитории: `vault` (требуется Vault для проверки токена) и `https://kubernetes.default.svc` (требуется Kubernetes API для успешного выполнения TokenReview). После применения SecretStore успешно подключился к Vault, статус `Ready: True`.

### Команды и конфиги
Создайте файл `secretstore.yaml`:

```yaml
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: vault
spec:
  provider:
    vault:
      server: "http://vault-server.vault.svc.cluster.local:8200"
      path: "otus"
      version: "v1"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "otus"
          serviceAccountRef:
            name: "vault-auth"
            audiences:
              - vault
              - https://kubernetes.default.svc
```

Примените манифест (одинаково для PowerShell и Bash):

```bash
kubectl apply -f secretstore.yaml
```

### Валидация
Проверьте статус SecretStore (PowerShell):

```powershell
kubectl get secretstore -n vault vault-backend -o jsonpath="{.status.conditions[?(@.type=='Ready')].status}"
# Ожидается: True
```

Проверьте статус SecretStore (Bash):

```bash
kubectl get secretstore -n vault vault-backend -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
# Ожидается: True
```

Проверьте подробное состояние SecretStore:

```bash
kubectl describe secretstore vault-backend -n vault
# В Events не должно быть ошибок 403 permission denied или InvalidProviderConfig
# В Status должно быть Ready: True
```

Если статус `False`, принудительно запустите перепроверку (PowerShell):

```powershell
kubectl annotate secretstore vault-backend -n vault force-reconcile="$(Get-Date -UFormat %s)" --overwrite
```

Если статус `False`, принудительно запустите перепроверку (Bash):

```bash
kubectl annotate secretstore vault-backend -n vault force-reconcile="$(date +%s)" --overwrite
```

## 12. Создание ExternalSecret

### Описание
В namespace `vault` создан объект `ExternalSecret` с именем `otus-cred`. Он ссылается на `SecretStore vault-backend`, указывает целевой Kubernetes Secret `otus-cred` и извлекает из Vault-секрета `otus/cred` два ключа: `username` и `password`. После применения ExternalSecret External Secrets Operator синхронизировал данные и создал Kubernetes Secret `otus-cred` с ключами `username` и `password`, значения которых совпадают с сохранёнными в Vault (`otus` / `asajkjkahs`). Статус ExternalSecret — `SecretSynced`.

### Команды и конфиги
Создайте файл `externalsecret.yaml`:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: otus-cred
  namespace: vault
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: otus-cred
  data:
    - secretKey: username
      remoteRef:
        key: cred
        property: username
    - secretKey: password
      remoteRef:
        key: cred
        property: password
```

Примените манифест (одинаково для PowerShell и Bash):

```bash
kubectl apply -f externalsecret.yaml
```

### Валидация
Проверьте статус ExternalSecret (PowerShell):

```powershell
kubectl get externalsecret -n vault otus-cred -o jsonpath="{.status.conditions[?(@.type=='Ready')].reason}"
# Ожидается: SecretSynced
```

Проверьте статус ExternalSecret (Bash):

```bash
kubectl get externalsecret -n vault otus-cred -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}'
# Ожидается: SecretSynced
```

Проверьте, что Kubernetes Secret создан:

```bash
kubectl get secret -n vault otus-cred
# Ожидается: Secret otus-cred существует
```

Проверьте наличие ключей в Secret:

```bash
kubectl get secret -n vault otus-cred -o jsonpath="{.data}"
# Ожидается: {"password":"...","username":"..."}
```

Декодируйте значения и сверьте с Vault (PowerShell):

```powershell
kubectl get secret -n vault otus-cred -o jsonpath="{.data.username}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
# Ожидается: otus

kubectl get secret -n vault otus-cred -o jsonpath="{.data.password}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
# Ожидается: asajkjkahs
```

Декодируйте значения и сверьте с Vault (Bash):

```bash
kubectl get secret -n vault otus-cred -o jsonpath='{.data.username}' | base64 -d
# Ожидается: otus

kubectl get secret -n vault otus-cred -o jsonpath='{.data.password}' | base64 -d
# Ожидается: asajkjkahs
```

Если ExternalSecret не синхронизировался, принудительно запустите перепроверку (PowerShell):

```powershell
kubectl annotate externalsecret otus-cred -n vault force-reconcile="$(Get-Date -UFormat %s)" --overwrite
```

Если ExternalSecret не синхронизировался, принудительно запустите перепроверку (Bash):

```bash
kubectl annotate externalsecret otus-cred -n vault force-reconcile="$(date +%s)" --overwrite
```

## 13. Итоговый чек-лист выполнения задания

### Описание
Все пункты задания выполнены в полном объёме в локальном кластере Minikube (Yandex Cloud не использовался). Ниже приведён итоговый чек-лист с указанием статуса и команд для проверки каждого пункта.

### Команды и конфиги
Проверка выполнения всех пунктов задания (одинаково для PowerShell и Bash):

```bash
# 1. Кластер Minikube с 3 нодами
kubectl get nodes
# Ожидается: minikube, minikube-m02, minikube-m03 — все Ready

# 2. Consul с 3 репликами сервера в namespace consul
kubectl get pods -n consul
# Ожидается: 3 пода consul-0, consul-1, consul-2 в статусе Running

# 3. Vault с 3 репликами в namespace vault
kubectl get pods -n vault
# Ожидается: 3 пода vault-server-0, vault-server-1, vault-server-2 в статусе 1/1 Running

# 4. Vault использует Consul как storage backend в HA-режиме
kubectl exec -n vault vault-server-0 -- vault status
# Ожидается: Storage Type: consul, HA Enabled: true, Sealed: false

# 5. Секрет otus/cred создан в Vault
kubectl exec -n vault vault-server-0 -- vault kv get otus/cred
# Ожидается: username=otus, password=asajkjkahs

# 6. ServiceAccount vault-auth и ClusterRoleBinding созданы
kubectl get sa vault-auth -n vault
kubectl get clusterrolebinding vault-auth-delegator
# Ожидается: оба ресурса существуют

# 7. auth/kubernetes включён и сконфигурирован
kubectl exec -n vault vault-server-0 -- vault auth list
kubectl exec -n vault vault-server-0 -- vault read auth/kubernetes/config
# Ожидается: метод kubernetes/ включён, kubernetes_host = https://kubernetes.default.svc

# 8. Политика otus-policy создана
kubectl exec -n vault vault-server-0 -- vault policy read otus-policy
# Ожидается: path "otus/cred" { capabilities = ["read", "list"] }

# 9. Роль auth/kubernetes/role/otus создана
kubectl exec -n vault vault-server-0 -- vault read auth/kubernetes/role/otus
# Ожидается: bound_service_account_names = [vault-auth], audience = vault

# 10. External Secrets Operator установлен
kubectl get pods -n vault -l app.kubernetes.io/name=external-secrets
# Ожидается: поды ESO в статусе Running

# 11. SecretStore vault-backend создан и подключён к Vault
kubectl get secretstore -n vault vault-backend -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
# Ожидается: True

# 12. ExternalSecret otus-cred создан и синхронизирован
kubectl get externalsecret -n vault otus-cred -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}'
# Ожидается: SecretSynced

# 13. Kubernetes Secret otus-cred создан с двумя ключами
kubectl get secret -n vault otus-cred
kubectl get secret -n vault otus-cred -o jsonpath='{.data}'
# Ожидается: Secret существует, содержит ключи username и password
```

### Валидация
Проверьте значения ключей в созданном Secret и сверьте с Vault (PowerShell):

```powershell
kubectl get secret -n vault otus-cred -o jsonpath="{.data.username}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
# Ожидается: otus

kubectl get secret -n vault otus-cred -o jsonpath="{.data.password}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
# Ожидается: asajkjkahs
```

Проверьте значения ключей в созданном Secret и сверьте с Vault (Bash):

```bash
kubectl get secret -n vault otus-cred -o jsonpath='{.data.username}' | base64 -d
# Ожидается: otus

kubectl get secret -n vault otus-cred -o jsonpath='{.data.password}' | base64 -d
# Ожидается: asajkjkahs
```

**Все пункты задания выполнены в полном объёме.**