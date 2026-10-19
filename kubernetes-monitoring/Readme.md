# Nginx + Nginx Prometheus Exporter + Prometheus Operator в minikube

## 1. Запуск кластера

```bash
minikube start --driver=docker
```

## 2. Установка kube-prometheus-stack

```bash
helm install prometheus oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack

```

Проверка, что всё поднялось:

```bash
kubectl get all
```

Дождаться статуса `Running` у подов `prometheus-*`, `alertmanager-*`, `grafana-*`.

## 3. Разворачивание nginx с экспортером

Применить манифесты (Deployment + ConfigMap + Service):

```bash
kubectl apply -f nginx-deployment.yml
kubectl apply -f nginx-service.yml
```

Применить ServiceMonitor (чтобы Prometheus начал собирать метрики):

```bash
kubectl apply -f nginx-servicemonitor.yml
```

## 4. Валидация

### 4.1 Поды запущены с двумя контейнерами

```bash
kubectl get pods -l app=nginx-stub
# Ожидается READY 2/2
```

### 4.2 ServiceMonitor виден Prometheus

```bash
kubectl get servicemonitor nginx-stub
```

### 4.3 Таргет в Prometheus в статусе UP

Открыть Prometheus UI:

```bash
minikube service prometheus-kube-prometheus-prometheus
```

Перейти в **Status → Targets**, найти `nginx-stub`, убедиться в статусе `UP`.

Альтернативно — через port-forward (если работает в вашей среде):

```bash
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090
# http://localhost:9090/targets
```

### 4.4 Проверка запроса в Prometheus

В UI Prometheus выполнить:

```promql
nginx_up
```

## 5. Доступ к Grafana

```bash
minikube service prometheus-grafana
# логин: admin, пароль: admin (или из Secret)
```

Пароль (Linux/macOS):

```bash
kubectl get secret prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode; echo
```

Пароль (PowerShell, Windows):

```powershell
kubectl get secret prometheus-grafana -o jsonpath="{.data.admin-password}" | %{[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_))}
```

## 7. Удаление

```bash
kubectl delete -f nginx-servicemonitor.yml
kubectl delete -f nginx-stub-with-exporter.yml
helm uninstall prometheus
```