# Kubernetes templating

## Requirements 
- Traefik Gateway API
- Gateway CRDs

## Helm install

```bash
helm install homework . -n homework --create-namespace
```

## Validate

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