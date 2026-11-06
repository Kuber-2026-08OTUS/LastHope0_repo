# Домашнее задание: Инфраструктурные ноды и установка ArgoCD

## 1. Настройка инфраструктурных нод

### 1.1. Добавление taint на infra-ноды

```bash
# Замените <infra-node> на имя вашей ноды
kubectl taint nodes <infra-node> node-role=infra:NoSchedule
```

**Проверка:**

```bash
kubectl describe node <infra-node> | Select-String "Taints"
# Taints: node-role=infra:NoSchedule
```

### 1.2. Добавление label на infra-ноды (для nodeSelector)

```bash
kubectl label nodes <infra-node> node-role=infra
```

**Проверка:**

```bash
kubectl get nodes --show-labels 

```
```bash
NAME           STATUS   ROLES           AGE   VERSION   LABELS
minikube       Ready    control-plane   13d   v1.37.0   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,kubernetes.io/arch=amd64,kubernetes.io/hostname=minikube,kubernetes.io/os=linux,minikube.k8s.io/commit=7a9f6a841470a207de8cf4bafcccee0969d8ba10,minikube.k8s.io/name=minikube,minikube.k8s.io/primary=true,minikube.k8s.io/updated_at=2026_10_19T20_58_34_0700,minikube.k8s.io/version=v1.39.0,node-role.kubernetes.io/control-plane=,node.kubernetes.io/exclude-from-external-load-balancers=,topology.hostpath.csi/node=minikube
minikube-m02   Ready    <none>          13d   v1.37.0   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,kubernetes.io/arch=amd64,kubernetes.io/hostname=minikube-m02,kubernetes.io/os=linux,minikube.k8s.io/commit=7a9f6a841470a207de8cf4bafcccee0969d8ba10,minikube.k8s.io/name=minikube,minikube.k8s.io/primary=false,minikube.k8s.io/updated_at=2026_10_19T20_59_23_0700,minikube.k8s.io/version=v1.39.0,node-role=infra
```


---

## 2. Установка ArgoCD через Helm

### 2.1. Добавление Helm-репозитория

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

### 2.2. Создание `argocd-values.yaml`

```yaml
# argocd-values.yaml
global:
  nodeSelector:
    node-role: infra
  tolerations:
    - key: "node-role"
      operator: "Equal"
      value: "infra"
      effect: "NoSchedule"
```

### 2.3. Команда установки

```bash
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f argocd-values.yaml
```

---

## 3. Проверка установки

### 3.1. Все Pod'ы ArgoCD запущены

```bash
kubectl get pods -n argocd
```

**Ожидаемо:** все Pod'ы в статусе `Running` (1/1).

### 3.2. Проверка, что Pod'ы на infra-нодах

```bash
kubectl get pods -n argocd -o wide
```

**Ожидаемо:** колонка `NODE` показывает **только** infra-ноды (те, на которые вы добавили taint и label).

---


# 4. Create Argocd project

```bash
kubectl apply -f project-otus.yml 
```

# 5. Argocd apps

## 5.1 Create Argocd apps

```bash
kubectl apply -f kubernetes-templating-app.yml
kubectl apply -f kubernetes-networking-app.yml
```

# 5.1 Validate

```bash
minikube service argocd-server -n argocd --https --url
```

Figure out the password for admin user
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

